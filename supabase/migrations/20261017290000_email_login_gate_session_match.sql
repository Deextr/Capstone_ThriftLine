-- Grant marketplace access when the current JWT session_id has a verified gate,
-- even if a newer unverified gate row exists from an abandoned login attempt.
-- When session_id is absent from the JWT, keep the latest-verified-gate fallback.

BEGIN;

CREATE OR REPLACE FUNCTION public._email_login_session_gate_grants_access(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    CASE
      WHEN public._jwt_session_id() IS NOT NULL THEN
        EXISTS (
          SELECT 1
          FROM public.email_login_session_gates g
          WHERE g.user_id = p_user_id
            AND g.session_id = public._jwt_session_id()
            AND g.verified_at IS NOT NULL
        )
      ELSE
        public._email_login_latest_gate_grants_access(p_user_id)
    END;
$$;

REVOKE ALL ON FUNCTION public._email_login_session_gate_grants_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._email_login_session_gate_grants_access(uuid) TO authenticated, service_role;

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
    OR public._email_login_session_gate_grants_access(auth.uid());
$$;

COMMENT ON FUNCTION public.auth_email_login_access_granted() IS
  'Password email sessions need a verified email_login_session_gates row for the JWT session_id when present; otherwise the latest verified gate.';

COMMIT;
