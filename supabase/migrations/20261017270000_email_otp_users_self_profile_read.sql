-- Allow authenticated users to read their own users row while email OTP is
-- pending. Without this, RESTRICTIVE email_login_otp on public.users hides
-- role/account_status and the admin portal treats super admins as buyers.

BEGIN;

DROP POLICY IF EXISTS email_login_otp_restrictive ON public.users;

CREATE POLICY email_login_otp_restrictive_select ON public.users
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    public.auth_email_login_access_granted()
    OR auth.uid() = user_id
  );

CREATE POLICY email_login_otp_restrictive_insert ON public.users
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_email_login_access_granted());

CREATE POLICY email_login_otp_restrictive_update ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  TO authenticated
  USING (public.auth_email_login_access_granted())
  WITH CHECK (public.auth_email_login_access_granted());

CREATE POLICY email_login_otp_restrictive_delete ON public.users
  AS RESTRICTIVE
  FOR DELETE
  TO authenticated
  USING (public.auth_email_login_access_granted());

COMMENT ON POLICY email_login_otp_restrictive_select ON public.users IS
  'Own profile readable for routing during email OTP; other rows still require a verified session gate.';

-- Fallback when the access JWT omits session_id: verify the latest open gate.
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

COMMIT;
