-- Phase 1 — revise existing user_verifications for real seller applications.

ALTER TABLE public.user_verifications
  ADD COLUMN IF NOT EXISTS shop_name character varying(80),
  ADD COLUMN IF NOT EXISTS shop_address text,
  ADD COLUMN IF NOT EXISTS barangay character varying(120),
  ADD COLUMN IF NOT EXISTS city character varying(120) DEFAULT 'Davao City',
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.users (user_id),
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS application_type character varying(32) NOT NULL DEFAULT 'seller',
  ADD COLUMN IF NOT EXISTS liveness_passed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS liveness_result jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.user_verifications
  DROP CONSTRAINT IF EXISTS user_verifications_application_type_check;
ALTER TABLE public.user_verifications
  ADD CONSTRAINT user_verifications_application_type_check
  CHECK (application_type IN ('seller', 'identity'));

ALTER TABLE public.user_verifications
  ALTER COLUMN submitted_at SET DEFAULT now();
ALTER TABLE public.user_verifications
  ALTER COLUMN verification_id SET DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS user_verifications_one_pending_per_user
  ON public.user_verifications (user_id)
  WHERE verification_status = 'pending'::verification_status_enum;

DROP TRIGGER IF EXISTS trg_user_verifications_updated_at ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_updated_at
BEFORE UPDATE ON public.user_verifications
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.enforce_user_verifications_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.role() = 'service_role' OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.verification_id IS DISTINCT FROM OLD.verification_id THEN
    RAISE EXCEPTION 'verification identity is immutable' USING ERRCODE = '42501';
  END IF;
  NEW.verification_status := OLD.verification_status;
  NEW.rejection_reason := OLD.rejection_reason;
  NEW.reviewed_by := OLD.reviewed_by;
  NEW.reviewed_at := OLD.reviewed_at;
  NEW.verified_at := OLD.verified_at;
  NEW.email_verified := OLD.email_verified;
  NEW.phone_verified := OLD.phone_verified;
  NEW.government_id_number := OLD.government_id_number;
  NEW.created_at := OLD.created_at;
  NEW.submitted_at := OLD.submitted_at;
  NEW.application_type := OLD.application_type;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_verifications_column_guard ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_column_guard
BEFORE UPDATE ON public.user_verifications
FOR EACH ROW EXECUTE FUNCTION public.enforce_user_verifications_column_guard();

ALTER TABLE public.user_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_verifications FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_verifications_select_own_or_admin ON public.user_verifications;
CREATE POLICY user_verifications_select_own_or_admin ON public.user_verifications
  FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS user_verifications_insert_own_pending ON public.user_verifications;
CREATE POLICY user_verifications_insert_own_pending ON public.user_verifications
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND verification_status = 'pending'::verification_status_enum
    AND application_type = 'seller'
    AND liveness_passed = true
    AND NOT public.is_approved_seller()
  );

DROP POLICY IF EXISTS user_verifications_update_own_pending_or_admin ON public.user_verifications;
CREATE POLICY user_verifications_update_own_pending_or_admin ON public.user_verifications
  FOR UPDATE
  USING (
    public.is_admin()
    OR (auth.uid() = user_id AND verification_status = 'pending'::verification_status_enum)
  )
  WITH CHECK (
    public.is_admin()
    OR (auth.uid() = user_id AND verification_status = 'pending'::verification_status_enum)
  );

GRANT SELECT, INSERT, UPDATE ON public.user_verifications TO authenticated;
