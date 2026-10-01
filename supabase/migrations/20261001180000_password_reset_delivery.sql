-- Password recovery is sent by the send-password-reset Edge Function through
-- the same Gmail SMTP secrets as email OTP. Supabase Auth's built-in mailer
-- is not used: it returns HTTP 500 "Error sending recovery email".
--
-- These helpers are service_role only. They must not be callable with the
-- anon or authenticated key, or a client could probe which emails exist.

CREATE TABLE IF NOT EXISTS public.password_reset_attempts (
  email_hash text PRIMARY KEY,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  last_attempt_at timestamptz NOT NULL DEFAULT now(),
  attempt_count integer NOT NULL DEFAULT 0,
  CONSTRAINT password_reset_attempts_count_nonnegative
    CHECK (attempt_count >= 0)
);

ALTER TABLE public.password_reset_attempts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.password_reset_attempts FROM PUBLIC;
REVOKE ALL ON TABLE public.password_reset_attempts FROM anon;
REVOKE ALL ON TABLE public.password_reset_attempts FROM authenticated;

COMMENT ON TABLE public.password_reset_attempts IS
  'Hashed password-reset rate limits. No client policies. service_role only via SECURITY DEFINER functions.';

-- Returns 'email' when this address has an email/password identity and may
-- receive a recovery link, 'oauth' when the account is Google/OAuth only,
-- or 'none' when no auth user exists. Does not return user ids.
CREATE OR REPLACE FUNCTION public.password_reset_account_kind(p_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_has_email boolean;
BEGIN
  IF p_email IS NULL OR length(trim(p_email)) = 0 OR length(p_email) > 320 THEN
    RETURN 'none';
  END IF;

  SELECT u.id
    INTO v_user_id
  FROM auth.users u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN 'none';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM auth.identities i
    WHERE i.user_id = v_user_id
      AND lower(COALESCE(i.provider, '')) = 'email'
  )
    INTO v_has_email;

  IF v_has_email THEN
    RETURN 'email';
  END IF;
  RETURN 'oauth';
END;
$$;

-- Returns 'ok', 'cooldown' (under 60 seconds), or 'hourly' (5 per hour).
CREATE OR REPLACE FUNCTION public.claim_password_reset_attempt(p_email_hash text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_inserted integer;
  v_window timestamptz;
  v_last timestamptz;
  v_count integer;
BEGIN
  IF p_email_hash IS NULL OR length(trim(p_email_hash)) < 32 THEN
    RAISE EXCEPTION 'invalid reset attempt' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.password_reset_attempts (
    email_hash, window_started_at, last_attempt_at, attempt_count
  )
  VALUES (trim(p_email_hash), v_now, v_now, 1)
  ON CONFLICT (email_hash) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 1 THEN
    RETURN 'ok';
  END IF;

  SELECT window_started_at, last_attempt_at, attempt_count
    INTO v_window, v_last, v_count
  FROM public.password_reset_attempts
  WHERE email_hash = trim(p_email_hash)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'ok';
  END IF;

  IF v_now - v_window >= interval '1 hour' THEN
    UPDATE public.password_reset_attempts
    SET window_started_at = v_now,
        last_attempt_at = v_now,
        attempt_count = 1
    WHERE email_hash = trim(p_email_hash);
    RETURN 'ok';
  END IF;

  IF v_now - v_last < interval '60 seconds' THEN
    RETURN 'cooldown';
  END IF;

  IF v_count >= 5 THEN
    RETURN 'hourly';
  END IF;

  UPDATE public.password_reset_attempts
  SET last_attempt_at = v_now,
      attempt_count = v_count + 1
  WHERE email_hash = trim(p_email_hash);

  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.password_reset_account_kind(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.password_reset_account_kind(text) FROM anon;
REVOKE ALL ON FUNCTION public.password_reset_account_kind(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.password_reset_account_kind(text) TO service_role;

REVOKE ALL ON FUNCTION public.claim_password_reset_attempt(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_password_reset_attempt(text) FROM anon;
REVOKE ALL ON FUNCTION public.claim_password_reset_attempt(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_password_reset_attempt(text) TO service_role;

COMMENT ON FUNCTION public.password_reset_account_kind(text) IS
  'Service-role only. email = password recovery allowed, oauth = Google/OAuth only, none = no auth user.';

COMMENT ON FUNCTION public.claim_password_reset_attempt(text) IS
  'Service-role only rate limit for password reset. Stores a hash, never the email address.';
