-- Seller applications require a verified account phone (users.is_phone_verified).
-- Approved sellers and admin/service paths are unchanged.

CREATE OR REPLACE FUNCTION public.user_has_verified_account_phone(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_user_id
      AND COALESCE(u.is_phone_verified, false)
      AND u.phone_number IS NOT NULL
      AND length(regexp_replace(u.phone_number, '\D', '', 'g')) = 11
      AND regexp_replace(u.phone_number, '\D', '', 'g') LIKE '09%'
  );
$$;

COMMENT ON FUNCTION public.user_has_verified_account_phone(uuid) IS
  'True when the user row has is_phone_verified and a valid 09XXXXXXXXX phone_number.';

REVOKE ALL ON FUNCTION public.user_has_verified_account_phone(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_verified_account_phone(uuid)
  TO authenticated, service_role, postgres;

CREATE OR REPLACE FUNCTION public.enforce_seller_application_verified_phone()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR auth.role() = 'service_role'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.application_type IS DISTINCT FROM 'seller' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.verification_status IS DISTINCT FROM 'pending'::public.verification_status_enum THEN
    RETURN NEW;
  END IF;

  IF NOT public.user_has_verified_account_phone(NEW.user_id) THEN
    RAISE EXCEPTION
      'Verify your Philippine mobile number before submitting a seller application.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_verifications_require_phone
  ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_require_phone
BEFORE INSERT OR UPDATE ON public.user_verifications
FOR EACH ROW
EXECUTE FUNCTION public.enforce_seller_application_verified_phone();

DROP POLICY IF EXISTS user_verifications_insert_own_pending ON public.user_verifications;
CREATE POLICY user_verifications_insert_own_pending ON public.user_verifications
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND verification_status = 'pending'::verification_status_enum
    AND application_type = 'seller'
    AND liveness_passed = true
    AND NOT public.is_approved_seller()
    AND public.user_has_verified_account_phone(auth.uid())
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
    OR (
      auth.uid() = user_id
      AND verification_status = 'pending'::verification_status_enum
      AND public.user_has_verified_account_phone(auth.uid())
    )
  );
