-- Seller submit was failing for two independent reasons:
--
-- 1. user_verifications.government_id_number is NOT NULL with no default.
--    Become a Seller no longer collects an ID number (photos are the evidence),
--    so every insert aborted before a row was stored.
--
-- 2. AFTER INSERT trg_user_verifications_submitted calls notify_user, which
--    inserts into notifications. That table has FORCE ROW LEVEL SECURITY and
--    no INSERT policy. On Supabase, postgres is not a superuser, so the
--    SECURITY DEFINER write was blocked and the verification insert rolled back.
--
-- Authenticated clients still cannot insert notifications: INSERT privilege
-- remains revoked from authenticated.

ALTER TABLE public.user_verifications
  ALTER COLUMN government_id_number DROP NOT NULL;

DROP POLICY IF EXISTS notifications_insert_definer ON public.notifications;
CREATE POLICY notifications_insert_definer ON public.notifications
  FOR INSERT
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.notify_verification_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    PERFORM public.notify_user(
      NEW.user_id,
      'verificationSubmitted',
      'Application submitted',
      'Your seller application is under review.',
      jsonb_build_object('verification_id', NEW.verification_id)
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
  RETURN NEW;
END;
$$;
