-- The first identity-link trigger blocked ANY second provider on the same
-- auth.users row. That also blocked Google sign-in when GoTrue tried to
-- attach a google identity onto an existing email/password user (same Gmail).
-- GoTrue surfaces that as HTTP 500 "Error creating identity", and the app
-- showed "Something went wrong".
--
-- The attack we actually need to stop is unauthenticated email/password
-- signup attaching an `email` identity (and a password) onto a Google user.
--
-- Allowed:
--   * first identity of any provider (new Google or new email user)
--   * inserting `google` (or other OAuth) onto an email/password user
--     with the same email — the user proved they own that Google account
--
-- Still blocked:
--   * inserting `email` onto a user who already has Google/OAuth

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

COMMENT ON FUNCTION public.prevent_cross_provider_identity_link() IS
  'Blocks attaching an email/password identity onto an OAuth user. Google sign-in onto an existing email user is allowed so one email stays one account.';
