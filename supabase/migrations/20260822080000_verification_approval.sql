CREATE OR REPLACE FUNCTION public.apply_verification_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status THEN
    RETURN NEW;
  END IF;

  IF NEW.verification_status = 'approved'::verification_status_enum THEN
    NEW.verified_at := COALESCE(NEW.verified_at, now());
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, now());
    IF NEW.reviewed_by IS NULL AND auth.uid() IS NOT NULL THEN
      NEW.reviewed_by := auth.uid();
    END IF;

    UPDATE public.users
    SET role = 'seller'::user_role_enum
    WHERE user_id = NEW.user_id
      AND role IS DISTINCT FROM 'admin'::user_role_enum;

    INSERT INTO public.seller_profiles (
      seller_id, shop_name, shop_address, barangay, city, is_approved, approved_at
    ) VALUES (
      NEW.user_id,
      COALESCE(NULLIF(TRIM(NEW.shop_name), ''), 'Shop'),
      NEW.shop_address,
      NEW.barangay,
      COALESCE(NULLIF(TRIM(NEW.city), ''), 'Davao City'),
      true,
      now()
    )
    ON CONFLICT (seller_id) DO UPDATE
      SET shop_name = COALESCE(NULLIF(TRIM(EXCLUDED.shop_name), ''), public.seller_profiles.shop_name),
          shop_address = COALESCE(EXCLUDED.shop_address, public.seller_profiles.shop_address),
          barangay = COALESCE(EXCLUDED.barangay, public.seller_profiles.barangay),
          city = COALESCE(EXCLUDED.city, public.seller_profiles.city),
          is_approved = true,
          approved_at = COALESCE(public.seller_profiles.approved_at, now());

    PERFORM public.notify_user(
      NEW.user_id,
      'verificationApproved',
      'You are now a verified seller',
      'Your seller application was approved. You can start listing items.',
      jsonb_build_object('verification_id', NEW.verification_id)
    );
  ELSIF NEW.verification_status = 'rejected'::verification_status_enum THEN
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, now());
    IF NEW.reviewed_by IS NULL AND auth.uid() IS NOT NULL THEN
      NEW.reviewed_by := auth.uid();
    END IF;
    PERFORM public.notify_user(
      NEW.user_id,
      'verificationRejected',
      'Seller application not approved',
      COALESCE(NULLIF(TRIM(NEW.rejection_reason), ''),
               'Your seller application was rejected. You can review the reason and reapply.'),
      jsonb_build_object('verification_id', NEW.verification_id)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_verifications_decision ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_decision
BEFORE UPDATE OF verification_status ON public.user_verifications
FOR EACH ROW EXECUTE FUNCTION public.apply_verification_decision();

CREATE OR REPLACE FUNCTION public.notify_verification_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.notify_user(
    NEW.user_id,
    'verificationSubmitted',
    'Application submitted',
    'Your seller application is under review.',
    jsonb_build_object('verification_id', NEW.verification_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_verifications_submitted ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_submitted
AFTER INSERT ON public.user_verifications
FOR EACH ROW EXECUTE FUNCTION public.notify_verification_submitted();

-- In-app admin calls this. is_admin() is required when a JWT is present.
CREATE OR REPLACE FUNCTION public.review_seller_verification(
  p_verification_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.is_admin()
  THEN
    RAISE EXCEPTION 'only an admin can review seller verifications' USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'decision must be approved or rejected';
  END IF;

  IF p_decision = 'rejected' AND NULLIF(TRIM(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'a rejection reason is required';
  END IF;

  UPDATE public.user_verifications v
  SET verification_status = p_decision::verification_status_enum,
      rejection_reason = CASE WHEN p_decision = 'rejected' THEN TRIM(p_reason) ELSE v.rejection_reason END,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE v.verification_id = p_verification_id
    AND v.verification_status = 'pending'::verification_status_enum;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'pending verification % not found', p_verification_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.review_seller_verification(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_seller_verification(uuid, text, text) TO authenticated, service_role, postgres;

CREATE OR REPLACE FUNCTION public.is_approved_seller()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.account_status = 'active'::account_status_enum
      AND (
        u.role = 'admin'::user_role_enum
        OR (
          u.role = 'seller'::user_role_enum
          AND EXISTS (
            SELECT 1 FROM public.seller_profiles sp
            WHERE sp.seller_id = u.user_id AND sp.is_approved = true
          )
        )
      )
  );
$$;
