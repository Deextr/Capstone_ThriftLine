-- Phase 11 — Seller trust score, Weighted Sum Model (IMRAD 2.3.2).
--
-- TS = 0.40*IV + 0.30*ST + 0.20*UR + 0.10*CR
-- Each criterion is an integer 0–100. The products of the published
-- weights and rubric scores are exact integers, so the stored total is
-- that integer. Table 16's sample is 72.
--
-- Scale stays 0–100. Table 19's 0–5 decimal is not used.
-- rating_count = 0 scores UR as 60 (Table 14 has no "no ratings" row).
-- A fully verified seller with no sales and no confirmed reports scores 62,
-- which is New Seller.
-- Confirmed reports are reports.status = action_taken only.
-- The class "Banned" is a label. This migration does not change account_status.
--
-- Paste this file into the Supabase SQL editor and run it once.
-- Idempotent. Does not edit earlier migrations.

-- ===========================================================================
-- 1. Stored result
-- ===========================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS trust_level text,
  ADD COLUMN IF NOT EXISTS trust_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS trust_breakdown jsonb;

COMMENT ON COLUMN public.users.trust_score IS
  'Seller trust total, 0–100, written only by recalculate_seller_trust.';

COMMENT ON COLUMN public.users.trust_level IS
  'Table 17 class. A display label. Does not suspend the account.';

COMMENT ON COLUMN public.users.trust_breakdown IS
  'Criterion scores iv, st, ur, cr and the 2.3.2 weights. Not a client input.';

COMMENT ON COLUMN public.users.trust_updated_at IS
  'When recalculate_seller_trust last wrote a changed score.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_trust_score_range'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_trust_score_range
      CHECK (trust_score >= 0 AND trust_score <= 100);
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_trust_level_check'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_trust_level_check
      CHECK (
        trust_level IS NULL
        OR trust_level IN (
          'Highly Trusted Seller',
          'Trusted Seller',
          'New Seller',
          'Under Review',
          'Banned'
        )
      );
  END IF;
END
$$;

-- ===========================================================================
-- 2. Column guard
-- ===========================================================================
-- Trust columns change only when thriftline.maintain_trust = 1.
-- That includes admins, service_role, and the SQL editor.
-- Role and account_status stay admin-writable. This does not ban anyone.

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('thriftline.maintain_trust', true) IS DISTINCT FROM '1' THEN
    NEW.trust_score     := OLD.trust_score;
    NEW.trust_level     := OLD.trust_level;
    NEW.trust_breakdown := OLD.trust_breakdown;
    NEW.trust_updated_at := OLD.trust_updated_at;
  END IF;

  IF auth.uid() IS NULL
     OR auth.role() = 'service_role'
     OR public.is_admin()
  THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.role              := OLD.role;
  NEW.account_status    := OLD.account_status;
  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Ordinary clients cannot write role, account_status, phone verification, or ratings. trust_score, trust_level, trust_breakdown, and trust_updated_at change only when thriftline.maintain_trust=1, including for admins.';

-- ===========================================================================
-- 3. Rubric. One place. No incremental plus or minus.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trust_iv_score(
  p_government boolean,
  p_email boolean,
  p_phone boolean,
  p_face boolean
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (CASE WHEN p_government THEN 25 ELSE 0 END)
    + (CASE WHEN p_email THEN 25 ELSE 0 END)
    + (CASE WHEN p_phone THEN 25 ELSE 0 END)
    + (CASE WHEN p_face THEN 25 ELSE 0 END);
$$;

CREATE OR REPLACE FUNCTION public.trust_st_score(p_count integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_count, 0) <= 0 THEN 0
    WHEN p_count <= 10 THEN 20
    WHEN p_count <= 20 THEN 40
    WHEN p_count <= 30 THEN 60
    WHEN p_count <= 50 THEN 80
    ELSE 100
  END;
$$;

CREATE OR REPLACE FUNCTION public.trust_ur_score(
  p_average numeric,
  p_count integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_count, 0) <= 0 OR p_average IS NULL THEN 60
    WHEN p_average >= 5 THEN 100
    WHEN p_average >= 4.5 THEN 90
    WHEN p_average >= 4.0 THEN 80
    WHEN p_average >= 3.5 THEN 70
    WHEN p_average >= 3.0 THEN 60
    ELSE 40
  END;
$$;

CREATE OR REPLACE FUNCTION public.trust_cr_score(p_count integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_count, 0) <= 0 THEN 100
    WHEN p_count = 1 THEN 80
    WHEN p_count = 2 THEN 60
    WHEN p_count = 3 THEN 40
    WHEN p_count = 4 THEN 20
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.trust_weighted_sum(
  p_iv integer,
  p_st integer,
  p_ur integer,
  p_cr integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(
    (0.40 * p_iv) + (0.30 * p_st) + (0.20 * p_ur) + (0.10 * p_cr)
  )::integer;
$$;

CREATE OR REPLACE FUNCTION public.trust_level_for(p_score integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_score >= 90 THEN 'Highly Trusted Seller'
    WHEN p_score >= 75 THEN 'Trusted Seller'
    WHEN p_score >= 60 THEN 'New Seller'
    WHEN p_score >= 40 THEN 'Under Review'
    ELSE 'Banned'
  END;
$$;

COMMENT ON FUNCTION public.trust_weighted_sum(integer, integer, integer, integer) IS
  'TS = 0.40*IV + 0.30*ST + 0.20*UR + 0.10*CR. Rubric inputs make this an exact integer.';

-- ===========================================================================
-- 4. Full recompute from current rows
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.recalculate_seller_trust(p_seller_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

  v_st := public.trust_st_score(v_completed);
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
    'completed_orders', v_completed,
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
  'Replaces the seller trust score from current verification, completed orders, ratings, and action_taken reports. Calling it twice writes the same score.';

REVOKE ALL ON FUNCTION public.recalculate_seller_trust(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recalculate_seller_trust(uuid) TO postgres, service_role;

-- ===========================================================================
-- 5. Triggers. Each one recomputes. None of them add or subtract points.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
     AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
     AND NEW.email_verified IS NOT DISTINCT FROM OLD.email_verified
     AND NEW.phone_verified IS NOT DISTINCT FROM OLD.phone_verified
     AND NEW.liveness_passed IS NOT DISTINCT FROM OLD.liveness_passed
  THEN
    RETURN NEW;
  END IF;

  PERFORM public.recalculate_seller_trust(NEW.user_id);
  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM public.recalculate_seller_trust(OLD.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_verifications_seller_trust
  ON public.user_verifications;
CREATE TRIGGER trg_user_verifications_seller_trust
AFTER INSERT OR UPDATE ON public.user_verifications
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_verification();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_phone()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recalculate_seller_trust(NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_phone_seller_trust ON public.users;
CREATE TRIGGER trg_users_phone_seller_trust
AFTER UPDATE OF is_phone_verified ON public.users
FOR EACH ROW
WHEN (OLD.is_phone_verified IS DISTINCT FROM NEW.is_phone_verified)
EXECUTE FUNCTION public.trg_seller_trust_from_phone();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.order_status IS NOT DISTINCT FROM OLD.order_status
     AND NEW.seller_id IS NOT DISTINCT FROM OLD.seller_id
  THEN
    RETURN NEW;
  END IF;
  PERFORM public.recalculate_seller_trust(NEW.seller_id);
  IF OLD.seller_id IS DISTINCT FROM NEW.seller_id THEN
    PERFORM public.recalculate_seller_trust(OLD.seller_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_seller_trust ON public.orders;
CREATE TRIGGER trg_orders_seller_trust
AFTER UPDATE OF order_status, seller_id ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_order();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_escrow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.seller_id IS NOT DISTINCT FROM OLD.seller_id
  THEN
    RETURN NEW;
  END IF;
  PERFORM public.recalculate_seller_trust(NEW.seller_id);
  IF TG_OP = 'UPDATE' AND OLD.seller_id IS DISTINCT FROM NEW.seller_id THEN
    PERFORM public.recalculate_seller_trust(OLD.seller_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_escrow_seller_trust ON public.escrow;
CREATE TRIGGER trg_escrow_seller_trust
AFTER INSERT OR UPDATE OF status, seller_id ON public.escrow
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_escrow();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_dispute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_seller uuid;
BEGIN
  SELECT o.seller_id
    INTO v_seller
  FROM public.orders o
  WHERE o.order_id = NEW.order_id;

  PERFORM public.recalculate_seller_trust(v_seller);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_disputes_seller_trust
  ON public.delivery_disputes;
CREATE TRIGGER trg_delivery_disputes_seller_trust
AFTER INSERT OR UPDATE OF status ON public.delivery_disputes
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_dispute();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recalculate_seller_trust(OLD.reviewed_user_id);
    RETURN OLD;
  END IF;

  PERFORM public.recalculate_seller_trust(NEW.reviewed_user_id);
  IF TG_OP = 'UPDATE'
     AND NEW.reviewed_user_id IS DISTINCT FROM OLD.reviewed_user_id
  THEN
    PERFORM public.recalculate_seller_trust(OLD.reviewed_user_id);
  END IF;
  RETURN NEW;
END;
$$;

-- Name sorts after trg_reviews_rating_aggregate so rating_count is current.
DROP TRIGGER IF EXISTS trg_reviews_trust_recalc ON public.reviews;
CREATE TRIGGER trg_reviews_trust_recalc
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_review();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.reported_user_id IS NOT DISTINCT FROM OLD.reported_user_id
  THEN
    RETURN NEW;
  END IF;
  PERFORM public.recalculate_seller_trust(NEW.reported_user_id);
  IF OLD.reported_user_id IS DISTINCT FROM NEW.reported_user_id THEN
    PERFORM public.recalculate_seller_trust(OLD.reported_user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reports_seller_trust ON public.reports;
CREATE TRIGGER trg_reports_seller_trust
AFTER UPDATE OF status, reported_user_id ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_report();

CREATE OR REPLACE FUNCTION public.trg_seller_trust_from_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recalculate_seller_trust(NEW.seller_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seller_profiles_seller_trust ON public.seller_profiles;
CREATE TRIGGER trg_seller_profiles_seller_trust
AFTER INSERT OR UPDATE OF is_approved ON public.seller_profiles
FOR EACH ROW
EXECUTE FUNCTION public.trg_seller_trust_from_profile();

-- ===========================================================================
-- 6. Public projection: score and class. Breakdown stays on users.
-- ===========================================================================

DROP VIEW IF EXISTS public.user_public_profiles;

CREATE VIEW public.user_public_profiles
WITH (security_invoker = false) AS
SELECT
  u.user_id,
  u.username,
  u.full_name,
  u.avatar,
  u.role,
  u.trust_score,
  u.trust_level,
  u.rating_average,
  u.rating_count,
  u.created_at
FROM public.users u
WHERE u.account_status = 'active'::account_status_enum;

COMMENT ON VIEW public.user_public_profiles IS
  'Non-sensitive projection of public.users. Includes trust_score and trust_level. Excludes email, phone, account_status, and trust_breakdown.';

GRANT SELECT ON public.user_public_profiles TO anon, authenticated;

-- ===========================================================================
-- 7. Replace placeholder scores for existing shops
-- ===========================================================================

DO $$
DECLARE
  v_seller uuid;
BEGIN
  FOR v_seller IN
    SELECT sp.seller_id
    FROM public.seller_profiles sp
  LOOP
    PERFORM public.recalculate_seller_trust(v_seller);
  END LOOP;
END
$$;
