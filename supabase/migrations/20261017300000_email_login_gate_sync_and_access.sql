-- Fix false "finish email verification" states:
-- 1) JWT session_id can change on refresh without a gate row (inherit prior verification).
-- 2) Pending OTP must block even when an older verified gate exists.
-- 3) Authenticated clients can sync the current session gate after refresh.

BEGIN;

CREATE OR REPLACE FUNCTION public._email_login_session_gate_grants_access(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  WITH jwt AS (
    SELECT public._jwt_session_id() AS sid
  )
  SELECT
    CASE
      WHEN (SELECT sid FROM jwt) IS NULL THEN
        public._email_login_latest_gate_grants_access(p_user_id)
      ELSE
        EXISTS (
          SELECT 1
          FROM public.email_login_session_gates g, jwt j
          WHERE g.user_id = p_user_id
            AND g.session_id = j.sid
            AND g.verified_at IS NOT NULL
        )
        OR (
          NOT EXISTS (
            SELECT 1
            FROM public.email_login_session_gates g, jwt j
            WHERE g.user_id = p_user_id
              AND g.session_id = j.sid
          )
          AND EXISTS (
            SELECT 1
            FROM public.email_login_session_gates g
            WHERE g.user_id = p_user_id
              AND g.verified_at IS NOT NULL
          )
        )
    END;
$$;

REVOKE ALL ON FUNCTION public._email_login_session_gate_grants_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._email_login_session_gate_grants_access(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sync_email_login_session_gate_from_verified()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_session_id uuid := public._jwt_session_id();
  v_verified_at timestamptz;
BEGIN
  IF v_user_id IS NULL OR v_session_id IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.email_login_session_gates g
    WHERE g.user_id = v_user_id
      AND g.session_id = v_session_id
      AND g.verified_at IS NOT NULL
  ) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.email_login_session_gates g
    WHERE g.user_id = v_user_id
      AND g.session_id = v_session_id
      AND g.verified_at IS NULL
  ) THEN
    RETURN false;
  END IF;

  SELECT g.verified_at
  INTO v_verified_at
  FROM public.email_login_session_gates g
  WHERE g.user_id = v_user_id
    AND g.verified_at IS NOT NULL
  ORDER BY g.verified_at DESC
  LIMIT 1;

  IF v_verified_at IS NULL THEN
    RETURN false;
  END IF;

  INSERT INTO public.email_login_session_gates (session_id, user_id, verified_at)
  VALUES (v_session_id, v_user_id, v_verified_at)
  ON CONFLICT (session_id) DO UPDATE
  SET
    user_id = EXCLUDED.user_id,
    verified_at = COALESCE(
      public.email_login_session_gates.verified_at,
      EXCLUDED.verified_at
    );

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_email_login_session_gate_from_verified() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_email_login_session_gate_from_verified() TO authenticated, service_role;

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
  'Password email sessions need a verified gate for the JWT session_id, or prior verification when refresh drift left no row.';

COMMIT;
