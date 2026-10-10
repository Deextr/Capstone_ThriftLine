-- Super Admin authorization, invitations, and audit attribution.
-- users.role remains the only authority. admin_profiles stores metadata only.

-- ---------------------------------------------------------------------------
-- Role helpers. is_admin() includes both administrator roles so existing
-- moderation policies keep working. is_super_admin() is the management gate.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.role IN (
        'admin'::public.user_role_enum,
        'super_admin'::public.user_role_enum
      )
      AND u.account_status = 'active'::public.account_status_enum
  );
$$;

COMMENT ON FUNCTION public.is_admin() IS
  'True when the current JWT belongs to an active admin or super admin.';

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.role = 'super_admin'::public.user_role_enum
      AND u.account_status = 'active'::public.account_status_enum
  );
$$;

COMMENT ON FUNCTION public.is_super_admin() IS
  'True when the current JWT belongs to an active super admin.';

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_approved_seller()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.account_status = 'active'::public.account_status_enum
      AND (
        u.role IN (
          'admin'::public.user_role_enum,
          'super_admin'::public.user_role_enum
        )
        OR (
          u.role = 'seller'::public.user_role_enum
          AND EXISTS (
            SELECT 1
            FROM public.seller_profiles sp
            WHERE sp.seller_id = u.user_id
              AND sp.is_approved = true
          )
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Column guard. Ordinary admins can still sanction buyers and sellers and
-- can still promote a buyer to seller during verification. They cannot
-- change administrator rows or grant admin roles.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('thriftline.maintain_trust', true) IS DISTINCT FROM '1' THEN
    NEW.trust_score      := OLD.trust_score;
    NEW.trust_level      := OLD.trust_level;
    NEW.trust_breakdown  := OLD.trust_breakdown;
    NEW.trust_updated_at := OLD.trust_updated_at;
  END IF;

  IF auth.uid() IS NULL OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSIF public.is_admin()
          AND current_setting('thriftline.seller_promotion', true) = '1'
          AND OLD.role = 'buyer'::public.user_role_enum
          AND NEW.role = 'seller'::public.user_role_enum THEN
      NULL;
    ELSE
      NEW.role := OLD.role;
    END IF;
  END IF;

  IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
    IF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSIF public.is_admin()
          AND OLD.role IN (
            'buyer'::public.user_role_enum,
            'seller'::public.user_role_enum
          )
          AND NEW.role IN (
            'buyer'::public.user_role_enum,
            'seller'::public.user_role_enum
          ) THEN
      NULL;
    ELSE
      NEW.account_status := OLD.account_status;
    END IF;
  END IF;

  IF OLD.role = 'super_admin'::public.user_role_enum
     AND OLD.account_status = 'active'::public.account_status_enum
     AND (
       NEW.role IS DISTINCT FROM 'super_admin'::public.user_role_enum
       OR NEW.account_status IS DISTINCT FROM 'active'::public.account_status_enum
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.users u
       WHERE u.role = 'super_admin'::public.user_role_enum
         AND u.account_status = 'active'::public.account_status_enum
         AND u.user_id <> OLD.user_id
     )
  THEN
    RAISE EXCEPTION 'the last active super admin cannot be deactivated or demoted'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Clients cannot grant admin roles. Active admins may sanction marketplace users and promote buyers to sellers. Super-admin account changes require thriftline.admin_mgmt. The last active super admin cannot be removed by an authenticated session.';

-- ---------------------------------------------------------------------------
-- Seller approval must not demote an administrator.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_verification_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_phone boolean := false;
BEGIN
  IF NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status THEN
    RETURN NEW;
  END IF;

  IF NEW.verification_status = 'approved'::public.verification_status_enum THEN
    NEW.verified_at := COALESCE(NEW.verified_at, now());
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, now());
    IF NEW.reviewed_by IS NULL AND auth.uid() IS NOT NULL THEN
      NEW.reviewed_by := auth.uid();
    END IF;

    NEW.email_verified := public.trust_seller_email_verified(NEW.user_id);
    SELECT COALESCE(u.is_phone_verified, false)
      INTO v_phone
    FROM public.users u
    WHERE u.user_id = NEW.user_id;
    NEW.phone_verified := v_phone;

    PERFORM set_config('thriftline.seller_promotion', '1', true);
    UPDATE public.users
    SET role = 'seller'::public.user_role_enum
    WHERE user_id = NEW.user_id
      AND role NOT IN (
        'admin'::public.user_role_enum,
        'super_admin'::public.user_role_enum
      );
    PERFORM set_config('thriftline.seller_promotion', '0', true);

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
  ELSIF NEW.verification_status = 'rejected'::public.verification_status_enum THEN
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

CREATE OR REPLACE FUNCTION public.review_seller_verification(
  p_verification_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.is_admin()
  THEN
    RAISE EXCEPTION 'only an admin can review seller verifications' USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'decision must be approved or rejected';
  END IF;

  IF p_decision = 'rejected' AND NULLIF(TRIM(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'a rejection reason is required';
  END IF;

  UPDATE public.user_verifications v
  SET verification_status = p_decision::public.verification_status_enum,
      rejection_reason = CASE
        WHEN p_decision = 'rejected' THEN TRIM(p_reason)
        ELSE v.rejection_reason
      END,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE v.verification_id = p_verification_id
    AND v.verification_status = 'pending'::public.verification_status_enum;

  IF NOT FOUND THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.user_verifications
      WHERE verification_id = p_verification_id
    ) INTO v_exists;
    IF v_exists THEN
      RAISE EXCEPTION
        'This case has already been reviewed by another administrator. Refresh to view the latest decision.';
    END IF;
    RAISE EXCEPTION 'pending verification % not found', p_verification_id;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Administrator metadata and invitations. Role and access status stay on
-- public.users so there is one authority.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.admin_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE CASCADE,
  created_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  deactivated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.admin_invitations (
  invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  full_name text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  invited_by uuid NOT NULL REFERENCES public.users (user_id),
  auth_user_id uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_invitations_status_check CHECK (
    status IN ('pending', 'accepted', 'revoked', 'expired')
  ),
  CONSTRAINT admin_invitations_email_check CHECK (
    email = lower(email) AND position('@' IN email) > 1
  ),
  CONSTRAINT admin_invitations_name_check CHECK (
    char_length(btrim(full_name)) BETWEEN 2 AND 80
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_invitations_one_pending_email
  ON public.admin_invitations (email)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS admin_invitations_auth_user_idx
  ON public.admin_invitations (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

ALTER TABLE public.admin_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_invitations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.admin_profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.admin_invitations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.admin_profiles TO authenticated;
GRANT SELECT ON TABLE public.admin_invitations TO authenticated;

DROP POLICY IF EXISTS admin_profiles_select_super ON public.admin_profiles;
CREATE POLICY admin_profiles_select_super
  ON public.admin_profiles
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

DROP POLICY IF EXISTS admin_invitations_select_super ON public.admin_invitations;
CREATE POLICY admin_invitations_select_super
  ON public.admin_invitations
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Audit helper. Not granted to clients. Management and decision triggers
-- call it in the same transaction as the change.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.write_admin_audit_log(
  p_category text,
  p_event_type text,
  p_status text,
  p_summary text,
  p_actor uuid,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_actor uuid := COALESCE(p_actor, auth.uid());
  v_email text;
BEGIN
  IF p_category NOT IN (
    'authentication',
    'seller_verification',
    'reports_disputes',
    'account_management',
    'payments_escrow',
    'system_security'
  ) THEN
    RAISE EXCEPTION 'invalid audit category' USING ERRCODE = '22023';
  END IF;

  IF p_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid audit status' USING ERRCODE = '22023';
  END IF;

  SELECT u.email INTO v_email
  FROM public.users u
  WHERE u.user_id = v_actor;

  INSERT INTO public.admin_audit_logs (
    category,
    event_type,
    status,
    summary,
    actor_user_id,
    actor_email,
    target_type,
    target_id,
    details
  )
  VALUES (
    p_category,
    left(trim(p_event_type), 120),
    p_status,
    left(trim(p_summary), 500),
    v_actor,
    v_email,
    NULLIF(trim(COALESCE(p_target_type, '')), ''),
    NULLIF(trim(COALESCE(p_target_id, '')), ''),
    COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING log_id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.write_admin_audit_log(
  text, text, text, text, uuid, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_admin_audit_log(
  text, text, text, text, uuid, text, text, jsonb
) TO service_role;

CREATE OR REPLACE FUNCTION public.record_admin_audit_log(
  p_category text,
  p_event_type text,
  p_status text,
  p_summary text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_email text;
  v_details jsonb := COALESCE(p_details, '{}'::jsonb);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_category = 'account_management' THEN
    RAISE EXCEPTION 'account management audit is recorded by the server'
      USING ERRCODE = '42501';
  END IF;

  IF p_category NOT IN (
    'authentication',
    'seller_verification',
    'reports_disputes',
    'payments_escrow',
    'system_security'
  ) THEN
    RAISE EXCEPTION 'invalid audit category' USING ERRCODE = '22023';
  END IF;

  IF p_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid audit status' USING ERRCODE = '22023';
  END IF;

  IF p_event_type IS NULL OR length(trim(p_event_type)) = 0
     OR p_summary IS NULL OR length(trim(p_summary)) = 0 THEN
    RAISE EXCEPTION 'event_type and summary required' USING ERRCODE = '22023';
  END IF;

  SELECT u.email INTO v_email
  FROM public.users u
  WHERE u.user_id = auth.uid();

  INSERT INTO public.admin_audit_logs (
    category,
    event_type,
    status,
    summary,
    actor_user_id,
    actor_email,
    target_type,
    target_id,
    details
  )
  VALUES (
    p_category,
    trim(p_event_type),
    p_status,
    left(trim(p_summary), 500),
    auth.uid(),
    v_email,
    NULLIF(trim(p_target_type), ''),
    NULLIF(trim(p_target_id), ''),
    v_details
  )
  RETURNING log_id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_admin_audit_logs(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_actor_user_id uuid DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(trim(COALESCE(p_search, '')), '');
  v_category text := NULLIF(trim(COALESCE(p_category, '')), '');
  v_status text := NULLIF(trim(COALESCE(p_status, '')), '');
  v_total bigint;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'super admin access required' USING ERRCODE = '42501';
  END IF;

  IF v_category IS NOT NULL AND v_category <> 'all'
     AND v_category NOT IN (
       'authentication',
       'seller_verification',
       'reports_disputes',
       'account_management',
       'payments_escrow',
       'system_security'
     ) THEN
    RAISE EXCEPTION 'invalid category filter' USING ERRCODE = '22023';
  END IF;

  IF v_status IS NOT NULL AND v_status <> 'all'
     AND v_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid status filter' USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::bigint INTO v_total
  FROM public.admin_audit_logs l
  LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
  WHERE (v_category IS NULL OR v_category = 'all' OR l.category = v_category)
    AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
    AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
    AND (p_from IS NULL OR l.created_at >= p_from)
    AND (p_to IS NULL OR l.created_at < p_to)
    AND (
      v_search IS NULL
      OR l.summary ILIKE ('%' || v_search || '%')
      OR l.event_type ILIKE ('%' || v_search || '%')
      OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT
      l.log_id,
      l.created_at,
      l.category,
      l.event_type,
      l.status,
      l.summary,
      l.actor_user_id,
      l.actor_email,
      actor.full_name AS actor_full_name,
      actor.role::text AS actor_role,
      l.target_type,
      l.target_id,
      l.details
    FROM public.admin_audit_logs l
    LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
    WHERE (v_category IS NULL OR v_category = 'all' OR l.category = v_category)
      AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
      AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
      AND (p_from IS NULL OR l.created_at >= p_from)
      AND (p_to IS NULL OR l.created_at < p_to)
      AND (
        v_search IS NULL
        OR l.summary ILIKE ('%' || v_search || '%')
        OR l.event_type ILIKE ('%' || v_search || '%')
        OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
      )
    ORDER BY l.created_at DESC, l.log_id DESC
    LIMIT v_limit
    OFFSET v_offset
  ) x;

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Decision audit. Fires in the same transaction as the status change.
-- Service-role jobs are not attributed as administrator actions.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_admin_moderation_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new jsonb := to_jsonb(NEW);
  v_old jsonb := to_jsonb(OLD);
  v_event text;
  v_summary text;
  v_category text;
  v_target_type text;
  v_target_id text;
  v_old_status text;
  v_new_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'user_verifications' THEN
    v_old_status := v_old->>'verification_status';
    v_new_status := v_new->>'verification_status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'approved' THEN
      v_event := 'seller_verification_approved';
      v_summary := 'Approved seller verification';
    ELSIF v_new_status = 'rejected' THEN
      v_event := 'seller_verification_rejected';
      v_summary := 'Rejected seller verification';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'seller_verification';
    v_target_type := 'verification';
    v_target_id := v_new->>'verification_id';
  ELSIF TG_TABLE_NAME = 'reports' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'needs_more_evidence' THEN
      v_event := 'order_report_evidence_requested';
      v_summary := 'Requested evidence for an order report';
    ELSIF v_new_status IN ('resolved', 'dismissed') AND v_new->>'order_id' IS NOT NULL THEN
      v_event := 'order_report_closed';
      v_summary := 'Resolved an order report';
    ELSIF v_new_status IN ('resolved', 'dismissed') THEN
      v_event := 'report_decided';
      v_summary := 'Resolved a community report';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'reports_disputes';
    v_target_type := 'report';
    v_target_id := v_new->>'report_id';
  ELSIF TG_TABLE_NAME = 'looking_for_reports' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status NOT IN ('resolved', 'dismissed') THEN
      RETURN NEW;
    END IF;
    v_event := 'looking_for_report_decided';
    v_summary := 'Resolved a Looking For report';
    v_category := 'reports_disputes';
    v_target_type := 'looking_for_report';
    v_target_id := v_new->>'report_id';
  ELSIF TG_TABLE_NAME = 'delivery_disputes' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_old_status IS DISTINCT FROM 'open' OR v_new_status IS DISTINCT FROM 'resolved' THEN
      RETURN NEW;
    END IF;
    v_event := 'delivery_dispute_closed';
    v_summary := 'Resolved a delivery dispute';
    v_category := 'reports_disputes';
    v_target_type := 'dispute';
    v_target_id := v_new->>'dispute_id';
  ELSIF TG_TABLE_NAME = 'escrow' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'released' THEN
      v_event := 'delivery_payment_released';
      v_summary := 'Released escrow payment';
    ELSIF v_new_status = 'refunded' THEN
      v_event := 'delivery_payment_refunded';
      v_summary := 'Refunded escrow payment';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'payments_escrow';
    v_target_type := 'escrow';
    v_target_id := COALESCE(v_new->>'dispute_id', v_new->>'escrow_id');
  ELSE
    RETURN NEW;
  END IF;

  PERFORM public.write_admin_audit_log(
    v_category,
    v_event,
    'success',
    v_summary,
    auth.uid(),
    v_target_type,
    v_target_id,
    jsonb_build_object('status', v_new_status)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_user_verifications ON public.user_verifications;
CREATE TRIGGER trg_audit_user_verifications
AFTER UPDATE OF verification_status ON public.user_verifications
FOR EACH ROW
EXECUTE FUNCTION public.audit_admin_moderation_change();

DROP TRIGGER IF EXISTS trg_audit_reports ON public.reports;
CREATE TRIGGER trg_audit_reports
AFTER UPDATE OF status ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.audit_admin_moderation_change();

DROP TRIGGER IF EXISTS trg_audit_looking_for_reports ON public.looking_for_reports;
CREATE TRIGGER trg_audit_looking_for_reports
AFTER UPDATE OF status ON public.looking_for_reports
FOR EACH ROW
EXECUTE FUNCTION public.audit_admin_moderation_change();

DROP TRIGGER IF EXISTS trg_audit_delivery_disputes ON public.delivery_disputes;
CREATE TRIGGER trg_audit_delivery_disputes
AFTER UPDATE OF status ON public.delivery_disputes
FOR EACH ROW
EXECUTE FUNCTION public.audit_admin_moderation_change();

DROP TRIGGER IF EXISTS trg_audit_escrow ON public.escrow;
CREATE TRIGGER trg_audit_escrow
AFTER UPDATE OF status ON public.escrow
FOR EACH ROW
EXECUTE FUNCTION public.audit_admin_moderation_change();

-- ---------------------------------------------------------------------------
-- Invitation and account management. Callable only with the service role.
-- The actor id is checked against public.users because service-role calls
-- do not carry the Super Admin JWT.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._assert_super_admin_actor(p_actor uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_actor IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_actor
      AND u.role = 'super_admin'::public.user_role_enum
      AND u.account_status = 'active'::public.account_status_enum
  ) THEN
    RAISE EXCEPTION 'super admin access required' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public._assert_super_admin_actor(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.lookup_admin_invite_email(
  p_actor uuid,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_email text := lower(trim(COALESCE(p_email, '')));
  v_auth uuid;
  v_role public.user_role_enum;
  v_invitation uuid;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR char_length(v_email) > 320 THEN
    RETURN jsonb_build_object('result', 'invalid_email');
  END IF;

  SELECT i.invitation_id INTO v_invitation
  FROM public.admin_invitations i
  WHERE i.email = v_email
    AND i.status = 'pending'
  LIMIT 1;

  IF v_invitation IS NOT NULL THEN
    RETURN jsonb_build_object(
      'result', 'invitation_pending',
      'invitation_id', v_invitation
    );
  END IF;

  SELECT a.id INTO v_auth
  FROM auth.users a
  WHERE lower(a.email) = v_email
  LIMIT 1;

  SELECT u.role INTO v_role
  FROM public.users u
  WHERE lower(u.email) = v_email
     OR u.user_id = v_auth
  ORDER BY CASE WHEN u.user_id = v_auth THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_role IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object('result', 'buyer_or_seller');
  END IF;

  IF v_role IN (
    'admin'::public.user_role_enum,
    'super_admin'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object('result', 'administrator');
  END IF;

  IF v_auth IS NOT NULL OR v_role IS NOT NULL THEN
    RETURN jsonb_build_object('result', 'auth_only');
  END IF;

  RETURN jsonb_build_object('result', 'available');
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_admin_invite_email(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_admin_invite_email(uuid, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.begin_admin_invitation(
  p_actor uuid,
  p_email text,
  p_full_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email text := lower(trim(COALESCE(p_email, '')));
  v_name text := trim(COALESCE(p_full_name, ''));
  v_id uuid;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR char_length(v_email) > 320 THEN
    RAISE EXCEPTION 'invalid email' USING ERRCODE = '22023';
  END IF;

  IF char_length(v_name) < 2 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'invalid name' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.admin_invitations (
    email, full_name, status, invited_by, expires_at
  )
  VALUES (
    v_email, v_name, 'pending', p_actor, now() + interval '7 days'
  )
  RETURNING invitation_id INTO v_id;

  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'invitation pending' USING ERRCODE = '23505';
END;
$$;

REVOKE ALL ON FUNCTION public.begin_admin_invitation(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_admin_invitation(uuid, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abandon_admin_invitation(
  p_actor uuid,
  p_invitation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);
  DELETE FROM public.admin_invitations
  WHERE invitation_id = p_invitation_id
    AND status = 'pending'
    AND auth_user_id IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_admin_invitation(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.abandon_admin_invitation(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.attach_invited_admin(
  p_actor uuid,
  p_invitation_id uuid,
  p_auth_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_invite public.admin_invitations%ROWTYPE;
  v_auth_email text;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  SELECT * INTO v_invite
  FROM public.admin_invitations
  WHERE invitation_id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND OR v_invite.status <> 'pending' THEN
    RAISE EXCEPTION 'invitation is not pending' USING ERRCODE = '22023';
  END IF;

  SELECT lower(a.email) INTO v_auth_email
  FROM auth.users a
  WHERE a.id = p_auth_user_id;

  IF v_auth_email IS NULL OR v_auth_email <> v_invite.email THEN
    RAISE EXCEPTION 'invitation email does not match the auth user'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.users u WHERE u.user_id = p_auth_user_id
  ) THEN
    RAISE EXCEPTION 'profile not ready' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.users
  SET role = 'admin'::public.user_role_enum,
      full_name = v_invite.full_name,
      email = v_invite.email,
      account_status = 'active'::public.account_status_enum
  WHERE user_id = p_auth_user_id
    AND role NOT IN (
      'admin'::public.user_role_enum,
      'super_admin'::public.user_role_enum,
      'seller'::public.user_role_enum
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'existing account cannot be converted into an admin'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.admin_invitations
  SET auth_user_id = p_auth_user_id,
      updated_at = now()
  WHERE invitation_id = p_invitation_id;

  INSERT INTO public.admin_profiles (user_id, created_by)
  VALUES (p_auth_user_id, p_actor)
  ON CONFLICT (user_id) DO UPDATE
    SET created_by = COALESCE(public.admin_profiles.created_by, EXCLUDED.created_by),
        updated_at = now();

  PERFORM public.write_admin_audit_log(
    'account_management',
    'admin_invited',
    'success',
    'Invited an administrator',
    p_actor,
    'admin_invitation',
    p_invitation_id::text,
    jsonb_build_object('email', v_invite.email)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.attach_invited_admin(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.attach_invited_admin(uuid, uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_admin_invitation_resend(
  p_actor uuid,
  p_invitation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invite public.admin_invitations%ROWTYPE;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  SELECT * INTO v_invite
  FROM public.admin_invitations
  WHERE invitation_id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND OR v_invite.status NOT IN ('pending', 'expired') THEN
    RAISE EXCEPTION 'invitation cannot be resent' USING ERRCODE = '22023';
  END IF;

  IF v_invite.status = 'pending' AND v_invite.expires_at <= now() THEN
    UPDATE public.admin_invitations
    SET status = 'expired', updated_at = now()
    WHERE invitation_id = p_invitation_id;
    v_invite.status := 'expired';
  END IF;

  UPDATE public.admin_invitations
  SET status = 'pending',
      expires_at = now() + interval '7 days',
      updated_at = now()
  WHERE invitation_id = p_invitation_id;

  PERFORM public.write_admin_audit_log(
    'account_management',
    'admin_invitation_resent',
    'success',
    'Resent an administrator invitation',
    p_actor,
    'admin_invitation',
    p_invitation_id::text,
    jsonb_build_object('email', v_invite.email)
  );

  RETURN jsonb_build_object(
    'email', v_invite.email,
    'full_name', v_invite.full_name,
    'auth_user_id', v_invite.auth_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_admin_invitation_resend(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_admin_invitation_resend(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.revoke_admin_invitation(
  p_actor uuid,
  p_invitation_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invite public.admin_invitations%ROWTYPE;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  SELECT * INTO v_invite
  FROM public.admin_invitations
  WHERE invitation_id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND OR v_invite.status NOT IN ('pending', 'expired') THEN
    RAISE EXCEPTION 'invitation cannot be revoked' USING ERRCODE = '22023';
  END IF;

  UPDATE public.admin_invitations
  SET status = 'revoked',
      revoked_at = now(),
      updated_at = now()
  WHERE invitation_id = p_invitation_id;

  IF v_invite.auth_user_id IS NOT NULL THEN
    UPDATE public.users
    SET account_status = 'deactivated'::public.account_status_enum
    WHERE user_id = v_invite.auth_user_id
      AND role = 'admin'::public.user_role_enum;

    UPDATE public.admin_profiles
    SET deactivated_at = COALESCE(deactivated_at, now()),
        updated_at = now()
    WHERE user_id = v_invite.auth_user_id;
  END IF;

  PERFORM public.write_admin_audit_log(
    'account_management',
    'admin_invitation_revoked',
    'success',
    'Revoked an administrator invitation',
    p_actor,
    'admin_invitation',
    p_invitation_id::text,
    jsonb_build_object('email', v_invite.email)
  );

  RETURN v_invite.auth_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_admin_invitation(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_admin_invitation(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.set_admin_account_active(
  p_actor uuid,
  p_target uuid,
  p_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  IF p_target IS NULL OR p_target = p_actor THEN
    RAISE EXCEPTION 'this account cannot be changed' USING ERRCODE = '42501';
  END IF;

  SELECT u.role, u.account_status
    INTO v_role, v_status
  FROM public.users u
  WHERE u.user_id = p_target
  FOR UPDATE;

  IF NOT FOUND OR v_role IS DISTINCT FROM 'admin'::public.user_role_enum THEN
    RAISE EXCEPTION 'only a normal administrator can be changed here'
      USING ERRCODE = '42501';
  END IF;

  IF p_active THEN
    UPDATE public.users
    SET account_status = 'active'::public.account_status_enum
    WHERE user_id = p_target;

    UPDATE public.admin_profiles
    SET deactivated_at = NULL, updated_at = now()
    WHERE user_id = p_target;
  ELSE
    UPDATE public.users
    SET account_status = 'deactivated'::public.account_status_enum
    WHERE user_id = p_target;

    INSERT INTO public.admin_profiles (user_id, deactivated_at)
    VALUES (p_target, now())
    ON CONFLICT (user_id) DO UPDATE
      SET deactivated_at = now(), updated_at = now();
  END IF;

  PERFORM public.write_admin_audit_log(
    'account_management',
    CASE WHEN p_active THEN 'admin_activated' ELSE 'admin_deactivated' END,
    'success',
    CASE
      WHEN p_active THEN 'Activated an administrator'
      ELSE 'Deactivated an administrator'
    END,
    p_actor,
    'admin_user',
    p_target::text,
    jsonb_build_object('previous_status', v_status::text)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_admin_account_active(uuid, uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_admin_account_active(uuid, uuid, boolean)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_admin_invitation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_invite public.admin_invitations%ROWTYPE;
  v_role public.user_role_enum;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sign in first' USING ERRCODE = '42501';
  END IF;

  SELECT u.role INTO v_role
  FROM public.users u
  WHERE u.user_id = v_uid;

  IF v_role NOT IN (
    'admin'::public.user_role_enum,
    'super_admin'::public.user_role_enum
  ) THEN
    RAISE EXCEPTION 'invitation is invalid' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_invite
  FROM public.admin_invitations
  WHERE auth_user_id = v_uid
    AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    IF EXISTS (
      SELECT 1
      FROM public.admin_invitations
      WHERE auth_user_id = v_uid
        AND status = 'accepted'
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'invitation is invalid or has already been used'
      USING ERRCODE = '22023';
  END IF;

  IF v_invite.expires_at <= now() THEN
    UPDATE public.admin_invitations
    SET status = 'expired', updated_at = now()
    WHERE invitation_id = v_invite.invitation_id;
    RAISE EXCEPTION 'invitation has expired' USING ERRCODE = '22023';
  END IF;

  UPDATE public.admin_invitations
  SET status = 'accepted',
      accepted_at = now(),
      updated_at = now()
  WHERE invitation_id = v_invite.invitation_id;

  PERFORM public.write_admin_audit_log(
    'account_management',
    'admin_invitation_accepted',
    'success',
    'Accepted an administrator invitation',
    v_uid,
    'admin_invitation',
    v_invite.invitation_id::text,
    '{}'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_admin_invitation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_admin_invitation() TO authenticated;

CREATE OR REPLACE FUNCTION public.list_admin_accounts(
  p_search text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
  v_status text := NULLIF(lower(trim(COALESCE(p_status, ''))), '');
  v_role text := NULLIF(lower(trim(COALESCE(p_role, ''))), '');
  v_total bigint;
  v_rows jsonb;
  v_counts jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'super admin access required' USING ERRCODE = '42501';
  END IF;

  UPDATE public.admin_invitations
  SET status = 'expired', updated_at = now()
  WHERE status = 'pending'
    AND expires_at <= now();

  WITH accounts AS (
    SELECT
      u.user_id,
      u.full_name,
      u.email,
      u.role::text AS role,
      u.account_status::text AS account_status,
      u.created_at,
      au.last_sign_in_at,
      i.invitation_id,
      i.status AS invitation_status,
      ap.deactivated_at,
      CASE
        WHEN u.account_status IS DISTINCT FROM 'active'::public.account_status_enum
          THEN 'inactive'
        WHEN i.status = 'pending' THEN 'invited'
        WHEN i.status = 'expired' AND i.accepted_at IS NULL THEN 'invited'
        ELSE 'active'
      END AS display_status
    FROM public.users u
    LEFT JOIN auth.users au ON au.id = u.user_id
    LEFT JOIN public.admin_profiles ap ON ap.user_id = u.user_id
    LEFT JOIN LATERAL (
      SELECT invitation_id, status, accepted_at
      FROM public.admin_invitations inv
      WHERE inv.auth_user_id = u.user_id
      ORDER BY inv.created_at DESC
      LIMIT 1
    ) i ON true
    WHERE u.role IN (
      'admin'::public.user_role_enum,
      'super_admin'::public.user_role_enum
    )
  ),
  filtered AS (
    SELECT *
    FROM accounts a
    WHERE (v_role IS NULL OR v_role = 'all' OR a.role = v_role)
      AND (v_status IS NULL OR v_status = 'all' OR a.display_status = v_status)
      AND (
        v_search IS NULL
        OR lower(a.full_name) LIKE '%' || v_search || '%'
        OR lower(COALESCE(a.email, '')) LIKE '%' || v_search || '%'
      )
  )
  SELECT count(*)::bigint INTO v_total FROM filtered;

  WITH accounts AS (
    SELECT
      u.user_id,
      u.full_name,
      u.email,
      u.role::text AS role,
      u.account_status::text AS account_status,
      u.created_at,
      au.last_sign_in_at,
      i.invitation_id,
      i.status AS invitation_status,
      ap.deactivated_at,
      CASE
        WHEN u.account_status IS DISTINCT FROM 'active'::public.account_status_enum
          THEN 'inactive'
        WHEN i.status = 'pending' THEN 'invited'
        WHEN i.status = 'expired' AND i.accepted_at IS NULL THEN 'invited'
        ELSE 'active'
      END AS display_status
    FROM public.users u
    LEFT JOIN auth.users au ON au.id = u.user_id
    LEFT JOIN public.admin_profiles ap ON ap.user_id = u.user_id
    LEFT JOIN LATERAL (
      SELECT invitation_id, status, accepted_at
      FROM public.admin_invitations inv
      WHERE inv.auth_user_id = u.user_id
      ORDER BY inv.created_at DESC
      LIMIT 1
    ) i ON true
    WHERE u.role IN (
      'admin'::public.user_role_enum,
      'super_admin'::public.user_role_enum
    )
  ),
  filtered AS (
    SELECT *
    FROM accounts a
    WHERE (v_role IS NULL OR v_role = 'all' OR a.role = v_role)
      AND (v_status IS NULL OR v_status = 'all' OR a.display_status = v_status)
      AND (
        v_search IS NULL
        OR lower(a.full_name) LIKE '%' || v_search || '%'
        OR lower(COALESCE(a.email, '')) LIKE '%' || v_search || '%'
      )
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(page) ORDER BY page.created_at DESC), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT *
    FROM filtered
    ORDER BY created_at DESC, user_id
    LIMIT v_limit
    OFFSET v_offset
  ) page;

  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (WHERE display_status = 'active'),
    'inactive', count(*) FILTER (WHERE display_status = 'inactive'),
    'pending', count(*) FILTER (WHERE display_status = 'invited')
  )
  INTO v_counts
  FROM (
    SELECT
      CASE
        WHEN u.account_status IS DISTINCT FROM 'active'::public.account_status_enum
          THEN 'inactive'
        WHEN i.status = 'pending' THEN 'invited'
        WHEN i.status = 'expired' AND i.accepted_at IS NULL THEN 'invited'
        ELSE 'active'
      END AS display_status
    FROM public.users u
    LEFT JOIN LATERAL (
      SELECT status, accepted_at
      FROM public.admin_invitations inv
      WHERE inv.auth_user_id = u.user_id
      ORDER BY inv.created_at DESC
      LIMIT 1
    ) i ON true
    WHERE u.role IN (
      'admin'::public.user_role_enum,
      'super_admin'::public.user_role_enum
    )
  ) counts;

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'counts', v_counts,
    'rows', v_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_admin_accounts(text, text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_admin_accounts(text, text, text, integer, integer)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- One-time bootstrap. SQL editor only. Promotes one existing active admin
-- and refuses to run again once any super admin exists.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.promote_initial_super_admin(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'a user id is required' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE role = 'super_admin'::public.user_role_enum
      AND user_id <> p_user_id
  ) THEN
    RAISE EXCEPTION 'a super admin already exists' USING ERRCODE = '42501';
  END IF;

  SELECT u.role, u.account_status
    INTO v_role, v_status
  FROM public.users u
  WHERE u.user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found' USING ERRCODE = '22023';
  END IF;

  IF v_role = 'super_admin'::public.user_role_enum THEN
    RETURN 'unchanged';
  END IF;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum
     OR v_role IS DISTINCT FROM 'admin'::public.user_role_enum THEN
    RAISE EXCEPTION 'only an active admin can be promoted' USING ERRCODE = '42501';
  END IF;

  UPDATE public.users
  SET role = 'super_admin'::public.user_role_enum
  WHERE user_id = p_user_id;

  INSERT INTO public.admin_profiles (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM public.write_admin_audit_log(
    'account_management',
    'super_admin_designated',
    'success',
    'Designated the initial super admin',
    p_user_id,
    'admin_user',
    p_user_id::text,
    '{}'::jsonb
  );

  RETURN 'promoted';
END;
$$;

REVOKE ALL ON FUNCTION public.promote_initial_super_admin(uuid)
  FROM PUBLIC, anon, authenticated;

-- Explicit account requested for this project. This matches one email.
-- It does not promote the earliest signup, and it does nothing when that
-- auth user is missing or a super admin already exists.
DO $$
DECLARE
  v_uid uuid;
  v_role public.user_role_enum;
  v_status public.account_status_enum;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE role = 'super_admin'::public.user_role_enum
  ) THEN
    RETURN;
  END IF;

  SELECT a.id INTO v_uid
  FROM auth.users a
  WHERE lower(a.email) = 'dexter041711@gmail.com';

  IF v_uid IS NULL THEN
    RAISE NOTICE 'super admin designation skipped: dexter041711@gmail.com has no auth user';
    RETURN;
  END IF;

  SELECT u.role, u.account_status
    INTO v_role, v_status
  FROM public.users u
  WHERE u.user_id = v_uid;

  IF NOT FOUND THEN
    RAISE NOTICE 'super admin designation skipped: public profile is missing';
    RETURN;
  END IF;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RAISE NOTICE 'super admin designation skipped: account is not active';
    RETURN;
  END IF;

  IF v_role NOT IN (
    'admin'::public.user_role_enum,
    'buyer'::public.user_role_enum
  ) THEN
    RAISE NOTICE 'super admin designation skipped: role is %', v_role;
    RETURN;
  END IF;

  UPDATE public.users
  SET role = 'super_admin'::public.user_role_enum
  WHERE user_id = v_uid;

  INSERT INTO public.admin_profiles (user_id)
  VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

INSERT INTO public.admin_profiles (user_id)
SELECT u.user_id
FROM public.users u
WHERE u.role IN (
  'admin'::public.user_role_enum,
  'super_admin'::public.user_role_enum
)
ON CONFLICT (user_id) DO NOTHING;

DROP POLICY IF EXISTS admin_audit_logs_select_admin ON public.admin_audit_logs;
DROP POLICY IF EXISTS admin_audit_logs_select_super ON public.admin_audit_logs;
CREATE POLICY admin_audit_logs_select_super
  ON public.admin_audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

-- Security-definer callers run as the function owner. REVOKE FROM PUBLIC
-- removes the owner's inherited EXECUTE, so grant it back explicitly.
DO $$
DECLARE
  v_audit_owner name;
  v_actor_owner name;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO v_audit_owner
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'write_admin_audit_log'
  LIMIT 1;

  IF v_audit_owner IS NOT NULL THEN
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.write_admin_audit_log(text, text, text, text, uuid, text, text, jsonb) TO %I',
      v_audit_owner
    );
  END IF;

  SELECT pg_get_userbyid(proowner) INTO v_actor_owner
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = '_assert_super_admin_actor'
  LIMIT 1;

  IF v_actor_owner IS NOT NULL THEN
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public._assert_super_admin_actor(uuid) TO %I',
      v_actor_owner
    );
  END IF;
END;
$$;
