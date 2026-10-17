-- Bind a completed login OTP to the current GoTrue session_id.
-- Password grant, send-otp, and token refresh can register different session_ids;
-- verifying only one of them left is_admin() false after a successful OTP.

BEGIN;

CREATE OR REPLACE FUNCTION public._jwt_session_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_raw text;
BEGIN
  v_raw := NULLIF(btrim(COALESCE(auth.jwt()->>'session_id', '')), '');
  IF v_raw IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_raw !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NULL;
  END IF;
  RETURN v_raw::uuid;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._email_login_has_recent_consumed_otp(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.email_otp_challenges c
    WHERE c.user_id = p_user_id
      AND COALESCE(c.purpose, 'login_verify') = 'login_verify'
      AND c.consumed_at IS NOT NULL
      AND c.consumed_at > now() - interval '12 hours'
  );
$$;

REVOKE ALL ON FUNCTION public._email_login_has_recent_consumed_otp(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._email_login_has_recent_consumed_otp(uuid) TO service_role;

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
  );
$$;

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
              AND g.verified_at IS NULL
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

CREATE OR REPLACE FUNCTION public.verify_email_login_session_gate(
  p_session_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id uuid := COALESCE(p_user_id, auth.uid());
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.email_login_session_gates g
  SET verified_at = now()
  WHERE g.user_id = v_user_id
    AND g.verified_at IS NULL
    AND g.created_at > now() - interval '12 hours'
    AND (
      p_session_id IS NULL
      OR g.session_id = p_session_id
      OR g.created_at > now() - interval '45 minutes'
    );

  IF p_session_id IS NOT NULL THEN
    INSERT INTO public.email_login_session_gates (session_id, user_id, verified_at)
    VALUES (p_session_id, v_user_id, now())
    ON CONFLICT (session_id) DO UPDATE
    SET
      user_id = EXCLUDED.user_id,
      verified_at = COALESCE(
        public.email_login_session_gates.verified_at,
        now()
      )
    WHERE public.email_login_session_gates.user_id = v_user_id;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.email_login_session_gates g
    WHERE g.user_id = v_user_id
      AND g.verified_at IS NOT NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_email_login_session_gate_after_otp()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_session_id uuid := public._jwt_session_id();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT public._email_login_has_recent_consumed_otp(v_user_id) THEN
    RETURN public.auth_email_login_access_granted();
  END IF;

  RETURN public.verify_email_login_session_gate(v_session_id, v_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_email_login_session_gate_after_otp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_email_login_session_gate_after_otp() TO authenticated, service_role;

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
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF public._email_login_has_recent_consumed_otp(v_user_id) THEN
    RETURN public.verify_email_login_session_gate(v_session_id, v_user_id);
  END IF;

  IF v_session_id IS NULL THEN
    RETURN public.auth_email_login_access_granted();
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

  IF EXISTS (
    SELECT 1
    FROM public.email_login_session_gates g
    WHERE g.user_id = v_user_id
      AND g.session_id = v_session_id
      AND g.verified_at IS NULL
  ) THEN
    UPDATE public.email_login_session_gates g
    SET verified_at = v_verified_at
    WHERE g.user_id = v_user_id
      AND g.session_id = v_session_id
      AND g.verified_at IS NULL;
    RETURN true;
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
    OR public._email_login_session_gate_grants_access(auth.uid())
    OR (
      public._email_login_has_recent_consumed_otp(auth.uid())
      AND NOT EXISTS (
        SELECT 1
        FROM public.email_login_session_gates g
        WHERE g.user_id = auth.uid()
          AND g.session_id IS NOT DISTINCT FROM public._jwt_session_id()
          AND g.verified_at IS NULL
          AND g.created_at > (
            SELECT max(c.consumed_at)
            FROM public.email_otp_challenges c
            WHERE c.user_id = auth.uid()
              AND COALESCE(c.purpose, 'login_verify') = 'login_verify'
              AND c.consumed_at IS NOT NULL
          )
      )
    );
$$;

COMMENT ON FUNCTION public.auth_email_login_access_granted() IS
  'Password email sessions need a verified gate, or a login OTP consumed in the last 12 hours for this same session (not a later password grant).';

ALTER FUNCTION public._email_login_has_recent_consumed_otp(uuid) SET row_security = off;
ALTER FUNCTION public.claim_email_login_session_gate_after_otp() SET row_security = off;
ALTER FUNCTION public.sync_email_login_session_gate_from_verified() SET row_security = off;
ALTER FUNCTION public.auth_email_login_access_granted() SET row_security = off;
ALTER FUNCTION public.verify_email_login_session_gate(uuid, uuid) SET row_security = off;

COMMIT;
