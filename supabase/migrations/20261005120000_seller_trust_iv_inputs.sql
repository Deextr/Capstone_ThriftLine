-- Seller trust IV inputs: derive email/phone from auth + users on approved sellers.
-- Avoids partial IV (42/52) when verification flags were never written.
-- Defers trust recalc on seller_profiles INSERT until verification is approved.
--
-- Paste into Supabase SQL editor once. Idempotent.

-- ===========================================================================
-- 1. Email leg of Table 12 from auth.users (not only user_verifications flags)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trust_seller_email_verified(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT COALESCE(
    (
      SELECT
        (a.email_confirmed_at IS NOT NULL OR a.confirmed_at IS NOT NULL)
        OR (
          NULLIF(TRIM(a.email), '') IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM auth.identities i
            WHERE i.user_id = a.id
          )
        )
      FROM auth.users a
      WHERE a.id = p_user_id
    ),
    false
  );
$$;

COMMENT ON FUNCTION public.trust_seller_email_verified(uuid) IS
  'Table 12 email +25 when Supabase auth confirms email or the account has a linked identity.';

REVOKE ALL ON FUNCTION public.trust_seller_email_verified(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trust_seller_email_verified(uuid) TO postgres, service_role;

-- ===========================================================================
-- 2. recalculate_seller_trust — merge auth/users into IV flags
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.recalculate_seller_trust(p_seller_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_ver public.user_verifications%ROWTYPE;
  v_has_ver boolean := false;
  v_government boolean := false;
  v_email boolean := false;
  v_phone boolean := false;
  v_face boolean := false;
  v_completed integer := 0;
  v_external integer := 0;
  v_eligible integer := 0;
  v_reports integer := 0;
  v_iv integer;
  v_st integer;
  v_ur integer;
  v_cr integer;
  v_ts integer;
  v_level text;
  v_breakdown jsonb;
BEGIN
  IF p_seller_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.seller_profiles sp
    WHERE sp.seller_id = p_seller_id
  ) THEN
    RETURN NULL;
  END IF;

  SELECT *
    INTO v_user
  FROM public.users
  WHERE user_id = p_seller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT *
    INTO v_ver
  FROM public.user_verifications
  WHERE user_id = p_seller_id
  ORDER BY COALESCE(reviewed_at, updated_at, submitted_at, created_at) DESC,
           verification_id DESC
  LIMIT 1;
  v_has_ver := FOUND;

  v_phone := COALESCE(v_user.is_phone_verified, false);
  IF v_has_ver THEN
    v_government :=
      v_ver.verification_status = 'approved'::public.verification_status_enum;
    v_email := COALESCE(v_ver.email_verified, false);
    v_phone := v_phone OR COALESCE(v_ver.phone_verified, false);
    v_face := v_government AND COALESCE(v_ver.liveness_passed, false);
  END IF;

  IF v_government THEN
    v_email := v_email OR public.trust_seller_email_verified(p_seller_id);
  END IF;

  v_iv := public.trust_iv_score(v_government, v_email, v_phone, v_face);

  SELECT count(*)::integer
    INTO v_completed
  FROM public.orders o
  WHERE o.seller_id = p_seller_id
    AND o.order_status = 'completed'::public.order_status_enum
    AND NOT EXISTS (
      SELECT 1
      FROM public.escrow e
      WHERE e.order_id = o.order_id
        AND e.status IN (
          'refunded'::public.escrow_status_enum,
          'disputed'::public.escrow_status_enum
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = o.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    );

  SELECT LEAST(count(*)::integer, 10)
    INTO v_external
  FROM public.external_transactions t
  JOIN public.user_verifications v
    ON v.verification_id = t.verification_id
  WHERE t.user_id = p_seller_id
    AND t.review_status = 'verified'
    AND v.verification_status = 'approved'::public.verification_status_enum;

  v_eligible := v_external + v_completed;
  v_st := public.trust_st_score(v_eligible);
  v_ur := public.trust_ur_score(v_user.rating_average, v_user.rating_count);

  SELECT count(*)::integer
    INTO v_reports
  FROM public.reports r
  WHERE r.reported_user_id = p_seller_id
    AND r.status = 'action_taken'::public.report_status_enum;

  v_cr := public.trust_cr_score(v_reports);
  v_ts := public.trust_weighted_sum(v_iv, v_st, v_ur, v_cr);
  v_level := public.trust_level_for(v_ts);
  v_breakdown := jsonb_build_object(
    'iv', v_iv,
    'st', v_st,
    'ur', v_ur,
    'cr', v_cr,
    'weights', jsonb_build_object(
      'iv', 0.40,
      'st', 0.30,
      'ur', 0.20,
      'cr', 0.10
    ),
    'completed_orders', v_eligible,
    'verified_external', v_external,
    'completed_thriftline', v_completed,
    'eligible_transactions', v_eligible,
    'confirmed_reports', v_reports,
    'rating_count', COALESCE(v_user.rating_count, 0),
    'formula', '2.3.2'
  );

  IF v_user.trust_score IS NOT DISTINCT FROM v_ts::numeric
     AND v_user.trust_level IS NOT DISTINCT FROM v_level
     AND v_user.trust_breakdown IS NOT DISTINCT FROM v_breakdown
  THEN
    RETURN v_ts;
  END IF;

  PERFORM set_config('thriftline.maintain_trust', '1', true);
  BEGIN
    UPDATE public.users
    SET trust_score = v_ts,
        trust_level = v_level,
        trust_breakdown = v_breakdown,
        trust_updated_at = now()
    WHERE user_id = p_seller_id;
    PERFORM set_config('thriftline.maintain_trust', '0', true);
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM set_config('thriftline.maintain_trust', '0', true);
      RAISE;
  END;

  RETURN v_ts;
END;
$$;

COMMENT ON FUNCTION public.recalculate_seller_trust(uuid) IS
  'Recomputes seller trust. IV email uses verification flags or auth.users confirmation. ST uses verified external (max 10) plus completed orders.';

-- ===========================================================================
-- 3. On admin approval, persist IV flags on the verification row
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.apply_verification_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_phone boolean := false;
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

    NEW.email_verified := public.trust_seller_email_verified(NEW.user_id);
    SELECT COALESCE(u.is_phone_verified, false)
      INTO v_phone
    FROM public.users u
    WHERE u.user_id = NEW.user_id;
    NEW.phone_verified := v_phone;

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
      jsonb_build_object('verification_id', NEW.verification_id),
      'seller'::public.notification_audience_enum
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
      jsonb_build_object('verification_id', NEW.verification_id),
      'seller'::public.notification_audience_enum
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ===========================================================================
-- 4. Do not recompute trust on seller_profiles INSERT (verification still pending)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF NEW.is_approved IS NOT TRUE
     OR OLD.is_approved IS NOT DISTINCT FROM NEW.is_approved
  THEN
    RETURN NEW;
  END IF;

  PERFORM public.recalculate_seller_trust(NEW.seller_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seller_profiles_seller_trust ON public.seller_profiles;
CREATE TRIGGER trg_seller_profiles_seller_trust
AFTER UPDATE OF is_approved ON public.seller_profiles
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_profile();

-- ===========================================================================
-- 5. Backfill approved sellers
-- ===========================================================================

DO $$
DECLARE
  v_seller uuid;
BEGIN
  FOR v_seller IN
    SELECT sp.seller_id
    FROM public.seller_profiles sp
    WHERE sp.is_approved IS TRUE
  LOOP
    PERFORM public.recalculate_seller_trust(v_seller);
  END LOOP;
END
$$;
