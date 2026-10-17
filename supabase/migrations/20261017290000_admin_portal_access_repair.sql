-- Repairs admin portal data access after email OTP session gates (172600).
-- Safe to run if 172700/172800 were partially applied: replaces functions/policies idempotently.
-- Run on hosted Supabase via SQL editor when `supabase db push` history does not match.

BEGIN;

-- ---------------------------------------------------------------------------
-- Email OTP gate: latest verified session per user (JWT session_id optional)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._email_login_latest_gate_grants_access(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM (
      SELECT g.session_id, g.verified_at
      FROM public.email_login_session_gates g
      WHERE g.user_id = p_user_id
      ORDER BY g.created_at DESC
      LIMIT 1
    ) latest
    WHERE latest.verified_at IS NOT NULL
      AND (
        public._jwt_session_id() IS NULL
        OR latest.session_id = public._jwt_session_id()
      )
  );
$$;

REVOKE ALL ON FUNCTION public._email_login_latest_gate_grants_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._email_login_latest_gate_grants_access(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.auth_email_login_access_granted()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    auth.uid() IS NULL
    OR auth.role() = 'service_role'
    OR NOT public._jwt_is_password_email_session()
    OR public._email_login_latest_gate_grants_access(auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.verify_email_login_session_gate_for_user(
  p_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id uuid := COALESCE(p_user_id, auth.uid());
  v_session_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT g.session_id
  INTO v_session_id
  FROM public.email_login_session_gates g
  WHERE g.user_id = v_user_id
    AND g.verified_at IS NULL
  ORDER BY g.created_at DESC
  LIMIT 1;

  IF v_session_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.verify_email_login_session_gate(v_session_id, v_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.verify_email_login_session_gate_for_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_email_login_session_gate_for_user(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- users: read own profile while OTP pending (routing); writes still gated
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS email_login_otp_restrictive ON public.users;

DROP POLICY IF EXISTS email_login_otp_restrictive_select ON public.users;
CREATE POLICY email_login_otp_restrictive_select ON public.users
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    public.auth_email_login_access_granted()
    OR auth.uid() = user_id
  );

DROP POLICY IF EXISTS email_login_otp_restrictive_insert ON public.users;
CREATE POLICY email_login_otp_restrictive_insert ON public.users
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_email_login_access_granted());

DROP POLICY IF EXISTS email_login_otp_restrictive_update ON public.users;
CREATE POLICY email_login_otp_restrictive_update ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  TO authenticated
  USING (public.auth_email_login_access_granted())
  WITH CHECK (public.auth_email_login_access_granted());

DROP POLICY IF EXISTS email_login_otp_restrictive_delete ON public.users;
CREATE POLICY email_login_otp_restrictive_delete ON public.users
  AS RESTRICTIVE
  FOR DELETE
  TO authenticated
  USING (public.auth_email_login_access_granted());

-- ---------------------------------------------------------------------------
-- is_admin(): active role + email gate + portal idle session
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public._is_active_admin_user()
    AND public.auth_email_login_access_granted()
    AND (
      NOT EXISTS (
        SELECT 1
        FROM public.admin_portal_sessions s
        WHERE s.user_id = auth.uid()
      )
      OR public._admin_portal_session_is_live(auth.uid())
    );
$$;

-- Client diagnostic (no secrets); helps debug local admin refresh failures.
CREATE OR REPLACE FUNCTION public.admin_portal_access_status()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT jsonb_build_object(
    'signed_in', auth.uid() IS NOT NULL,
    'active_admin', public._is_active_admin_user(),
    'email_gate', public.auth_email_login_access_granted(),
    'portal_session_live', (
      NOT EXISTS (
        SELECT 1 FROM public.admin_portal_sessions s WHERE s.user_id = auth.uid()
      )
      OR public._admin_portal_session_is_live(auth.uid())
    ),
    'is_admin', public.is_admin()
  );
$$;

REVOKE ALL ON FUNCTION public.admin_portal_access_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_portal_access_status() TO authenticated, service_role;

COMMIT;
