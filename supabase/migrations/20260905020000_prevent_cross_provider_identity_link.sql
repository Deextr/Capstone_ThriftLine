-- One email → one ThriftLine account.
--
-- Only blocks attaching an email/password identity onto a user who already
-- signed in with Google/OAuth. That is the unauthenticated credential-attach
-- bug (email signup after Google login).
--
-- Google sign-in onto an existing email/password user is allowed: the user
-- proved they own that Google account, and both methods stay on one auth.users
-- row. Blocking that path made GoTrue return HTTP 500 "Error creating identity".
--
-- If this file was already applied with the older "any second provider" body,
-- run 20260907010000_allow_google_identity_on_email_user.sql next.

CREATE OR REPLACE FUNCTION public.prevent_cross_provider_identity_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, pg_temp
AS $$
BEGIN
  IF NEW.provider IS NOT NULL
     AND lower(NEW.provider) = 'email'
     AND EXISTS (
       SELECT 1
       FROM auth.identities i
       WHERE i.user_id = NEW.user_id
         AND lower(COALESCE(i.provider, '')) <> 'email'
         AND i.id IS DISTINCT FROM NEW.id
     ) THEN
    RAISE EXCEPTION 'An account with this email already exists'
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_cross_provider_identity_link
  ON auth.identities;

CREATE TRIGGER trg_prevent_cross_provider_identity_link
  BEFORE INSERT ON auth.identities
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_cross_provider_identity_link();

COMMENT ON FUNCTION public.prevent_cross_provider_identity_link() IS
  'Blocks attaching an email/password identity onto an OAuth user. Google sign-in onto an existing email user is allowed.';
