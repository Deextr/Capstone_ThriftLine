-- Push device tokens, chat message in-app notifications, audience fix for messages,
-- and async push dispatch (FCM via Edge Function). In-app inserts never fail on push errors.

-- ---------------------------------------------------------------------------
-- 1. Message audience inference (dual-role: seller inbox vs buyer inbox)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.infer_message_notification_audience(
  p_recipient_id uuid,
  p_sender_id uuid,
  p_conversation_id uuid
)
RETURNS public.notification_audience_enum
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_product_id uuid;
  v_seller_id uuid;
  v_recipient_is_seller boolean;
  v_sender_is_seller boolean;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  SELECT c.product_id
  INTO v_product_id
  FROM public.conversations c
  WHERE c.conversation_id = p_conversation_id;

  IF v_product_id IS NOT NULL THEN
    SELECT p.seller_id INTO v_seller_id
    FROM public.products p
    WHERE p.product_id = v_product_id;

    IF v_seller_id = p_recipient_id THEN
      RETURN 'seller'::public.notification_audience_enum;
    END IF;
    RETURN 'buyer'::public.notification_audience_enum;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.seller_profiles sp
    WHERE sp.seller_id = p_recipient_id AND sp.is_approved
  ) INTO v_recipient_is_seller;

  SELECT EXISTS (
    SELECT 1 FROM public.seller_profiles sp
    WHERE sp.seller_id = p_sender_id AND sp.is_approved
  ) INTO v_sender_is_seller;

  IF v_recipient_is_seller AND NOT v_sender_is_seller THEN
    RETURN 'seller'::public.notification_audience_enum;
  END IF;

  RETURN 'buyer'::public.notification_audience_enum;
END;
$$;

REVOKE ALL ON FUNCTION public.infer_message_notification_audience(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.infer_message_notification_audience(uuid, uuid, uuid)
  TO postgres, service_role;

-- Stop treating every message as buyer-only (legacy rows keep inferred audience on read).
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
  v_conversation_id uuid;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  IF p_type IN ('outbid', 'wonBid', 'saved') THEN
    RETURN 'buyer'::public.notification_audience_enum;
  END IF;

  IF p_type = 'message' THEN
    v_conversation_id := NULLIF(COALESCE(p_data->>'conversation_id', ''), '')::uuid;
    IF v_conversation_id IS NOT NULL THEN
      RETURN public.infer_message_notification_audience(
        p_user_id,
        NULLIF(COALESCE(p_data->>'sender_id', ''), '')::uuid,
        v_conversation_id
      );
    END IF;
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

  IF p_type = 'system'
     AND COALESCE(p_data ? 'payout_id', false)
  THEN
    RETURN 'seller'::public.notification_audience_enum;
  END IF;

  IF p_type = 'system'
     AND COALESCE(p_data->>'can_appeal', '') = 'true'
  THEN
    RETURN 'system'::public.notification_audience_enum;
  END IF;

  RETURN 'system'::public.notification_audience_enum;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Chat: in-app notification for the recipient (not the sender)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.messages_notify_recipient()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_a uuid;
  v_b uuid;
  v_recipient uuid;
  v_preview text;
  v_audience public.notification_audience_enum;
BEGIN
  SELECT c.participant_a, c.participant_b
  INTO v_a, v_b
  FROM public.conversations c
  WHERE c.conversation_id = NEW.conversation_id;

  IF v_a IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.sender_id = v_a THEN
    v_recipient := v_b;
  ELSIF NEW.sender_id = v_b THEN
    v_recipient := v_a;
  ELSE
    RETURN NEW;
  END IF;

  IF v_recipient IS NULL OR v_recipient = NEW.sender_id THEN
    RETURN NEW;
  END IF;

  v_preview := CASE
    WHEN NEW.message_type = 'image' THEN COALESCE(NULLIF(btrim(NEW.content), ''), 'Sent a photo')
    WHEN NEW.message_type = 'offer' THEN COALESCE(NULLIF(btrim(NEW.content), ''), 'Sent an offer')
    ELSE left(COALESCE(NEW.content, ''), 120)
  END;

  v_audience := public.infer_message_notification_audience(
    v_recipient,
    NEW.sender_id,
    NEW.conversation_id
  );

  BEGIN
    PERFORM public.notify_user(
      v_recipient,
      'message',
      'New message',
      v_preview,
      jsonb_build_object(
        'conversation_id', NEW.conversation_id,
        'sender_id', NEW.sender_id
      ),
      v_audience
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_notify_recipient ON public.messages;
CREATE TRIGGER trg_messages_notify_recipient
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_notify_recipient();

-- ---------------------------------------------------------------------------
-- 3. Device tokens (FCM)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.push_device_tokens (
  token_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  device_token text NOT NULL,
  platform text NOT NULL,
  app_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CONSTRAINT push_device_tokens_platform_chk CHECK (platform IN ('android', 'ios', 'web')),
  CONSTRAINT push_device_tokens_device_token_key UNIQUE (device_token)
);

CREATE INDEX IF NOT EXISTS push_device_tokens_user_active_idx
  ON public.push_device_tokens (user_id)
  WHERE revoked_at IS NULL;

ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_device_tokens FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.push_device_tokens FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.push_device_tokens TO authenticated;
GRANT ALL ON TABLE public.push_device_tokens TO postgres, service_role;

DROP POLICY IF EXISTS push_device_tokens_select_own ON public.push_device_tokens;
CREATE POLICY push_device_tokens_select_own ON public.push_device_tokens
  FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS push_device_tokens_insert_own ON public.push_device_tokens;
CREATE POLICY push_device_tokens_insert_own ON public.push_device_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS push_device_tokens_update_own ON public.push_device_tokens;
CREATE POLICY push_device_tokens_update_own ON public.push_device_tokens
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.register_push_device_token(
  p_device_token text,
  p_platform text,
  p_app_version text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token text := NULLIF(btrim(p_device_token), '');
  v_platform text := lower(NULLIF(btrim(p_platform), ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF v_token IS NULL OR v_platform IS NULL THEN
    RAISE EXCEPTION 'Invalid device token';
  END IF;
  IF v_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'Unsupported platform';
  END IF;

  INSERT INTO public.push_device_tokens (
    user_id, device_token, platform, app_version, last_seen_at, revoked_at
  ) VALUES (
    v_uid, v_token, v_platform, NULLIF(btrim(p_app_version), ''), now(), NULL
  )
  ON CONFLICT (device_token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        app_version = COALESCE(EXCLUDED.app_version, public.push_device_tokens.app_version),
        last_seen_at = now(),
        revoked_at = NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.register_push_device_token(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device_token(text, text, text)
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.revoke_push_device_token(p_device_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token text := NULLIF(btrim(p_device_token), '');
BEGIN
  IF v_uid IS NULL OR v_token IS NULL THEN
    RETURN;
  END IF;
  UPDATE public.push_device_tokens
  SET revoked_at = now()
  WHERE device_token = v_token
    AND user_id = v_uid
    AND revoked_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_push_device_token(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_push_device_token(text)
  TO authenticated, postgres, service_role;

CREATE TABLE IF NOT EXISTS public.push_notification_deliveries (
  notification_id uuid PRIMARY KEY
    REFERENCES public.notifications (notification_id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  success_count integer NOT NULL DEFAULT 0,
  failure_count integer NOT NULL DEFAULT 0,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.push_notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_notification_deliveries FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.push_notification_deliveries FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.push_notification_deliveries TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 4. Dispatch push after in-app row is stored (pg_net → Edge Function)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.dispatch_push_for_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_headers jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN NEW;
  END IF;

  v_headers := jsonb_build_object('Content-Type', 'application/json')
    || COALESCE(
      (
        SELECT jsonb_build_object(
          'x-push-dispatch-secret',
          ds.decrypted_secret
        )
        FROM vault.decrypted_secrets ds
        WHERE ds.name = 'push_dispatch_secret'
        LIMIT 1
      ),
      '{}'::jsonb
    );

  BEGIN
    PERFORM net.http_post(
      url := 'https://zakorrcmmswwzfihmcji.supabase.co/functions/v1/send-push-notification',
      headers := v_headers,
      body := jsonb_build_object('notification_id', NEW.notification_id),
      timeout_milliseconds := 15000
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_dispatch_push ON public.notifications;
CREATE TRIGGER trg_notifications_dispatch_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.dispatch_push_for_notification();
