-- Fix auth_email_login_access_granted when GoTrue JWTs omit session_id or the
-- claim does not match the registered gate row. Use the latest gate for the
-- user and require it to be verified (pending OTP still blocks API access).

BEGIN;

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

COMMENT ON FUNCTION public.auth_email_login_access_granted() IS
  'Password email sessions need the latest email_login_session_gates row verified. JWT session_id is honored when present.';

COMMIT;
