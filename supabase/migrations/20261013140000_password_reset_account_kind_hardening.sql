-- Tighten password-reset eligibility: only accounts with an email/password
-- credential may receive a recovery link (Google/OAuth-only and unknown emails
-- remain 'oauth' / 'none').

CREATE OR REPLACE FUNCTION public.password_reset_account_kind(p_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_has_email_identity boolean;
  v_has_password boolean;
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
    INTO v_has_email_identity;

  IF NOT v_has_email_identity THEN
    RETURN 'oauth';
  END IF;

  SELECT (
    u.encrypted_password IS NOT NULL
    AND length(u.encrypted_password) > 0
  )
    INTO v_has_password
  FROM auth.users u
  WHERE u.id = v_user_id;

  IF NOT COALESCE(v_has_password, false) THEN
    RETURN 'oauth';
  END IF;

  RETURN 'email';
END;
$$;

COMMENT ON FUNCTION public.password_reset_account_kind(text) IS
  'Service-role only. email = password recovery allowed, oauth = OAuth-only or no password credential, none = no auth user.';
