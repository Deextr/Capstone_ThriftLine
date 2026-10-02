-- Dual-role accounts: tag each notification with buyer / seller / system (account-wide).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_audience_enum') THEN
    CREATE TYPE public.notification_audience_enum AS ENUM ('buyer', 'seller', 'system');
  END IF;
END;
$$;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS audience public.notification_audience_enum;

-- Resolve audience from type + payload (backfill + legacy notify_user callers).
CREATE OR REPLACE FUNCTION public.infer_notification_audience(
  p_user_id uuid,
  p_type text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS public.notification_audience_enum
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order_id uuid;
  v_role text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  IF p_type IN (
    'outbid',
    'wonBid',
    'message',
    'saved'
  ) THEN
    RETURN 'buyer'::public.notification_audience_enum;
  END IF;

  IF p_type IN (
    'verificationSubmitted',
    'verificationApproved',
    'verificationRejected'
  ) THEN
    RETURN 'seller'::public.notification_audience_enum;
  END IF;

  IF p_type IN ('report_decision') THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  v_order_id := NULLIF(COALESCE(p_data->>'order_id', ''), '')::uuid;
  IF v_order_id IS NOT NULL THEN
    SELECT CASE
      WHEN o.buyer_id = p_user_id THEN 'buyer'
      WHEN o.seller_id = p_user_id THEN 'seller'
      ELSE NULL
    END
    INTO v_role
    FROM public.orders o
    WHERE o.order_id = v_order_id;

    IF v_role IS NOT NULL THEN
      RETURN v_role::public.notification_audience_enum;
    END IF;
  END IF;

  IF p_type IN ('review') AND v_order_id IS NOT NULL THEN
    SELECT CASE
      WHEN o.buyer_id = p_user_id THEN 'buyer'
      WHEN o.seller_id = p_user_id THEN 'seller'
      ELSE 'system'
    END
    INTO v_role
    FROM public.orders o
    WHERE o.order_id = v_order_id;
    IF v_role IS NOT NULL THEN
      RETURN v_role::public.notification_audience_enum;
    END IF;
  END IF;

  -- Payout / seller treasury notices (no order_id in payload).
  IF p_type = 'system'
     AND COALESCE(p_data ? 'payout_id', false)
  THEN
    RETURN 'seller'::public.notification_audience_enum;
  END IF;

  -- Account trust / appeals (reported party).
  IF p_type = 'system'
     AND COALESCE(p_data->>'can_appeal', '') = 'true'
  THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  RETURN 'system'::public.notification_audience_enum;
END;
$$;

UPDATE public.notifications n
SET audience = public.infer_notification_audience(n.user_id, n.type, n.data)
WHERE n.audience IS NULL;

ALTER TABLE public.notifications
  ALTER COLUMN audience SET NOT NULL;

CREATE INDEX IF NOT EXISTS notifications_user_audience_created_idx
  ON public.notifications (user_id, audience, created_at DESC);

-- Primary insert path: audience is explicit at creation time.
CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb,
  p_audience public.notification_audience_enum
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, data, audience)
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    COALESCE(p_data, '{}'::jsonb),
    p_audience
  )
  RETURNING notification_id INTO v_id;
  RETURN v_id;
END;
$$;

-- Legacy 5-arg signature used by existing RPC bodies; infers audience from context.
CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.notify_user(
    p_user_id,
    p_type,
    p_title,
    p_body,
    COALESCE(p_data, '{}'::jsonb),
    public.infer_notification_audience(p_user_id, p_type, COALESCE(p_data, '{}'::jsonb))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_user(uuid, text, text, text, jsonb, notification_audience_enum)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_user(uuid, text, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_user(uuid, text, text, text, jsonb, notification_audience_enum)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.notify_user(uuid, text, text, text, jsonb)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.enforce_notifications_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.role() = 'service_role' OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  NEW.notification_id := OLD.notification_id;
  NEW.user_id := OLD.user_id;
  NEW.type := OLD.type;
  NEW.title := OLD.title;
  NEW.body := OLD.body;
  NEW.data := OLD.data;
  NEW.audience := OLD.audience;
  NEW.created_at := OLD.created_at;
  IF NEW.is_read AND NEW.read_at IS NULL THEN
    NEW.read_at := now();
  END IF;
  IF NOT NEW.is_read THEN
    NEW.read_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- Explicit audience at source for verification + community reports.
CREATE OR REPLACE FUNCTION public.notify_verification_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    PERFORM public.notify_user(
      NEW.user_id,
      'verificationSubmitted',
      'Application submitted',
      'Your seller application is under review.',
      jsonb_build_object('verification_id', NEW.verification_id),
      'seller'::public.notification_audience_enum
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_verification_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status THEN
    RETURN NEW;
  END IF;

  IF NEW.verification_status = 'approved'::verification_status_enum THEN
    NEW.verified_at := COALESCE(NEW.verified_at, now());
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, now());
    IF NEW.reviewed_by IS NULL AND auth.uid() IS NOT NULL THEN
      NEW.reviewed_by := auth.uid();
    END IF;

    UPDATE public.users
    SET role = 'seller'::user_role_enum
    WHERE user_id = NEW.user_id
      AND role IS DISTINCT FROM 'admin'::user_role_enum;

    INSERT INTO public.seller_profiles (
      seller_id, shop_name, shop_address, barangay, city, is_approved, approved_at
    ) VALUES (
      NEW.user_id,
      COALESCE(NULLIF(TRIM(NEW.shop_name), ''), 'Shop'),
      NEW.shop_address,
      NEW.barangay,
      COALESCE(NULLIF(TRIM(NEW.city), ''), 'Davao City'),
      true,
      now()
    )
    ON CONFLICT (seller_id) DO UPDATE
      SET shop_name = COALESCE(NULLIF(TRIM(EXCLUDED.shop_name), ''), public.seller_profiles.shop_name),
          shop_address = COALESCE(EXCLUDED.shop_address, public.seller_profiles.shop_address),
          barangay = COALESCE(EXCLUDED.barangay, public.seller_profiles.barangay),
          city = COALESCE(EXCLUDED.city, public.seller_profiles.city),
          is_approved = true,
          approved_at = COALESCE(public.seller_profiles.approved_at, now());

    PERFORM public.notify_user(
      NEW.user_id,
      'verificationApproved',
      'You are now a verified seller',
      'Your seller application was approved. You can start listing items.',
      jsonb_build_object('verification_id', NEW.verification_id),
      'seller'::public.notification_audience_enum
    );
  ELSIF NEW.verification_status = 'rejected'::verification_status_enum THEN
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, now());
    IF NEW.reviewed_by IS NULL AND auth.uid() IS NOT NULL THEN
      NEW.reviewed_by := auth.uid();
    END IF;
    PERFORM public.notify_user(
      NEW.user_id,
      'verificationRejected',
      'Seller application not approved',
      COALESCE(NULLIF(TRIM(NEW.rejection_reason), ''),
               'Your seller application was rejected. You can review the reason and reapply.'),
      jsonb_build_object('verification_id', NEW.verification_id),
      'seller'::public.notification_audience_enum
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_report_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'under_review'::public.report_status_enum
     AND NEW.status IS DISTINCT FROM 'under_review'::public.report_status_enum
  THEN
    PERFORM public.notify_user(
      NEW.reporter_id,
      'report_decision',
      'Report update',
      'We reviewed your report. Open My Reports to see the decision.',
      jsonb_build_object(
        'report_id', NEW.report_id,
        'status', NEW.status::text
      ),
      'system'::public.notification_audience_enum
    );
    PERFORM public.notify_user(
      NEW.reported_user_id,
      'system',
      'Account review update',
      'A community report involving your account has been reviewed. Reporter details are not shared.',
      jsonb_build_object(
        'report_id', NEW.report_id,
        'can_appeal', true
      ),
      'system'::public.notification_audience_enum
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS public.notify_auction_event_once(
  uuid, text, text, text, uuid, text, jsonb
);

CREATE OR REPLACE FUNCTION public.notify_auction_event_once(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_auction_id uuid,
  p_event text,
  p_data jsonb DEFAULT '{}'::jsonb,
  p_audience public.notification_audience_enum DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_audience public.notification_audience_enum;
BEGIN
  IF p_user_id IS NULL OR p_auction_id IS NULL THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = p_user_id
      AND n.type = p_type
      AND n.data->>'auction_id' = p_auction_id::text
      AND COALESCE(n.data->>'event', '') = COALESCE(p_event, '')
  ) THEN
    RETURN;
  END IF;

  v_payload := COALESCE(p_data, '{}'::jsonb)
    || jsonb_build_object(
      'auction_id', p_auction_id,
      'event', p_event
    );

  v_audience := COALESCE(
    p_audience,
    public.infer_notification_audience(p_user_id, p_type, v_payload)
  );

  PERFORM public.notify_user(
    p_user_id,
    p_type,
    p_title,
    p_body,
    v_payload,
    v_audience
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_auction_event_once(
  uuid, text, text, text, uuid, text, jsonb, notification_audience_enum
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_auction_event_once(
  uuid, text, text, text, uuid, text, jsonb, notification_audience_enum
) TO postgres, service_role;
