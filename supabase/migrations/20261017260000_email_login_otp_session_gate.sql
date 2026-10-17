-- XSYS-002: Server-side email OTP gate for password-based Supabase sessions.
-- Password JWTs cannot read or write marketplace data until the session gate is
-- verified (email OTP or trusted-device skip registered by sign-in-with-email).

BEGIN;

CREATE TABLE IF NOT EXISTS public.email_login_session_gates (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS email_login_session_gates_user_idx
  ON public.email_login_session_gates (user_id, created_at DESC);

ALTER TABLE public.email_login_session_gates ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.email_login_session_gates FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.email_login_session_gates TO service_role, postgres;

COMMENT ON TABLE public.email_login_session_gates IS
  'Tracks whether a GoTrue session_id from a password login may access marketplace APIs.';

-- ---------------------------------------------------------------------------
-- JWT helpers (password / oauth / recovery detection)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._jwt_amr_methods()
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT lower(
        COALESCE(
          elem->>'method',
          NULLIF(trim(both '"' FROM elem::text), '')
        )
      )
      FROM jsonb_array_elements(
        CASE jsonb_typeof(COALESCE(auth.jwt()->'amr', '[]'::jsonb))
          WHEN 'array' THEN COALESCE(auth.jwt()->'amr', '[]'::jsonb)
          ELSE '[]'::jsonb
        END
      ) AS elem
      WHERE COALESCE(
        elem->>'method',
        NULLIF(trim(both '"' FROM elem::text), '')
      ) IS NOT NULL
    ),
    ARRAY[]::text[]
  );
$$;

REVOKE ALL ON FUNCTION public._jwt_amr_methods() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._jwt_amr_methods() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._jwt_session_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(trim(both ' ' FROM COALESCE(auth.jwt()->>'session_id', '')), '')::uuid;
$$;

REVOKE ALL ON FUNCTION public._jwt_session_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._jwt_session_id() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._jwt_is_password_email_session()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND auth.role() = 'authenticated'
    AND NOT ('oauth' = ANY (public._jwt_amr_methods()))
    AND NOT ('recovery' = ANY (public._jwt_amr_methods()))
    AND (
      'password' = ANY (public._jwt_amr_methods())
      OR (
        COALESCE(auth.jwt()->'app_metadata'->>'provider', '') = 'email'
        AND NOT EXISTS (
          SELECT 1
          FROM unnest(public._jwt_amr_methods()) AS m(method)
          WHERE m.method NOT IN ('password', 'email')
        )
      )
    );
$$;

REVOKE ALL ON FUNCTION public._jwt_is_password_email_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._jwt_is_password_email_session() TO authenticated, service_role;

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
    OR EXISTS (
      SELECT 1
      FROM public.email_login_session_gates g
      WHERE g.session_id = public._jwt_session_id()
        AND g.user_id = auth.uid()
        AND g.verified_at IS NOT NULL
    );
$$;

COMMENT ON FUNCTION public.auth_email_login_access_granted() IS
  'False for password email sessions until email_login_session_gates is verified for this JWT session_id.';

REVOKE ALL ON FUNCTION public.auth_email_login_access_granted() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_email_login_access_granted() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.register_email_login_session_gate(
  p_session_id uuid,
  p_user_id uuid,
  p_trusted_skip boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF p_session_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid email login session gate' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.email_login_session_gates (session_id, user_id, verified_at)
  VALUES (
    p_session_id,
    p_user_id,
    CASE WHEN COALESCE(p_trusted_skip, false) THEN now() ELSE NULL END
  )
  ON CONFLICT (session_id) DO UPDATE
  SET
    user_id = EXCLUDED.user_id,
    verified_at = COALESCE(
      public.email_login_session_gates.verified_at,
      EXCLUDED.verified_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.register_email_login_session_gate(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_email_login_session_gate(uuid, uuid, boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.ensure_email_login_session_gate(
  p_session_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF p_session_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid email login session gate' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.email_login_session_gates (session_id, user_id)
  VALUES (p_session_id, p_user_id)
  ON CONFLICT (session_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_email_login_session_gate(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_email_login_session_gate(uuid, uuid) TO service_role;

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
  v_updated integer;
  v_user_id uuid := COALESCE(p_user_id, auth.uid());
BEGIN
  IF p_session_id IS NULL OR v_user_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.email_login_session_gates g
  SET verified_at = now()
  WHERE g.session_id = p_session_id
    AND g.user_id = v_user_id
    AND g.verified_at IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated > 0 THEN
    RETURN true;
  END IF;

  INSERT INTO public.email_login_session_gates (session_id, user_id, verified_at)
  VALUES (p_session_id, v_user_id, now())
  ON CONFLICT (session_id) DO UPDATE
  SET verified_at = COALESCE(
    public.email_login_session_gates.verified_at,
    now()
  )
  WHERE public.email_login_session_gates.user_id = v_user_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_email_login_session_gate(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_email_login_session_gate(uuid, uuid) TO service_role;

-- Admin authorization must respect the same email OTP gate as marketplace RLS.
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

COMMENT ON FUNCTION public.is_admin() IS
  'Active admin/super_admin with email OTP satisfied and portal idle rules when applicable.';

-- Restrictive RLS gate on every public table that already uses RLS.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname AS tablename
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity = true
      AND c.relname NOT IN ('email_login_session_gates', 'users')
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS email_login_otp_restrictive ON public.%I',
      r.tablename
    );
    EXECUTE format(
      $pol$
      CREATE POLICY email_login_otp_restrictive ON public.%1$I
        AS RESTRICTIVE
        FOR ALL
        TO authenticated
        USING (public.auth_email_login_access_granted())
        WITH CHECK (public.auth_email_login_access_granted())
      $pol$,
      r.tablename
    );
    EXECUTE format(
      'ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',
      r.tablename
    );
  END LOOP;
END $$;

DROP POLICY IF EXISTS email_login_otp_restrictive ON public.users;
CREATE POLICY email_login_otp_restrictive ON public.users
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (public.auth_email_login_access_granted())
  WITH CHECK (public.auth_email_login_access_granted());

COMMIT;
