-- Phase 11 checks for the seller trust Weighted Sum Model.
-- Run after 20260930190000_seller_trust_wsm.sql.
-- The SELECT expects every row to be PASS.
-- The DO block at the bottom checks a direct trust_score write and a second
-- recompute. It restores the row if the guard fails, then raises.

WITH checks AS (
  SELECT 1 AS seq, 'sample IV 100 ST 20 UR 90 CR 80 is 72' AS check_name,
         public.trust_weighted_sum(100, 20, 90, 80) = 72 AS ok
  UNION ALL SELECT 2, 'weights of 100 are 100',
         public.trust_weighted_sum(100, 100, 100, 100) = 100
  UNION ALL SELECT 3, 'lowest rubric path is 8',
         public.trust_weighted_sum(0, 0, 40, 0) = 8
  UNION ALL SELECT 4, 'verified seller with no reviews is 62',
         public.trust_weighted_sum(
           public.trust_iv_score(true, true, true, true),
           public.trust_st_score(0),
           public.trust_ur_score(NULL, 0),
           public.trust_cr_score(0)
         ) = 62
  UNION ALL SELECT 5, '62 is New Seller',
         public.trust_level_for(62) = 'New Seller'
  UNION ALL SELECT 6, '100 and 90 are Highly Trusted Seller',
         public.trust_level_for(100) = 'Highly Trusted Seller'
         AND public.trust_level_for(90) = 'Highly Trusted Seller'
  UNION ALL SELECT 7, '89 and 75 are Trusted Seller',
         public.trust_level_for(89) = 'Trusted Seller'
         AND public.trust_level_for(75) = 'Trusted Seller'
  UNION ALL SELECT 8, '74 and 60 are New Seller',
         public.trust_level_for(74) = 'New Seller'
         AND public.trust_level_for(60) = 'New Seller'
  UNION ALL SELECT 9, '59 and 40 are Under Review',
         public.trust_level_for(59) = 'Under Review'
         AND public.trust_level_for(40) = 'Under Review'
  UNION ALL SELECT 10, '39 and 0 are Banned',
         public.trust_level_for(39) = 'Banned'
         AND public.trust_level_for(0) = 'Banned'
  UNION ALL SELECT 11, 'IV parts are 25 and the full set is 100',
         public.trust_iv_score(true, false, false, false) = 25
         AND public.trust_iv_score(false, true, false, false) = 25
         AND public.trust_iv_score(false, false, true, false) = 25
         AND public.trust_iv_score(false, false, false, true) = 25
         AND public.trust_iv_score(true, true, true, true) = 100
         AND public.trust_iv_score(false, false, false, false) = 0
  UNION ALL SELECT 12, 'ST band edges match Table 13',
         public.trust_st_score(0) = 0
         AND public.trust_st_score(1) = 20
         AND public.trust_st_score(10) = 20
         AND public.trust_st_score(11) = 40
         AND public.trust_st_score(20) = 40
         AND public.trust_st_score(21) = 60
         AND public.trust_st_score(30) = 60
         AND public.trust_st_score(31) = 80
         AND public.trust_st_score(50) = 80
         AND public.trust_st_score(51) = 100
  UNION ALL SELECT 13, 'UR no-rating is 60 and Table 14 edges hold',
         public.trust_ur_score(NULL, 0) = 60
         AND public.trust_ur_score(0, 0) = 60
         AND public.trust_ur_score(5.0, 1) = 100
         AND public.trust_ur_score(4.9, 1) = 90
         AND public.trust_ur_score(4.5, 1) = 90
         AND public.trust_ur_score(4.49, 1) = 80
         AND public.trust_ur_score(4.0, 1) = 80
         AND public.trust_ur_score(3.5, 1) = 70
         AND public.trust_ur_score(3.0, 1) = 60
         AND public.trust_ur_score(2.99, 1) = 40
  UNION ALL SELECT 14, 'CR counts only the Table 15 steps',
         public.trust_cr_score(0) = 100
         AND public.trust_cr_score(1) = 80
         AND public.trust_cr_score(2) = 60
         AND public.trust_cr_score(3) = 40
         AND public.trust_cr_score(4) = 20
         AND public.trust_cr_score(5) = 0
  UNION ALL SELECT 15, 'same inputs do not drift',
         public.trust_weighted_sum(100, 20, 90, 80)
           = public.trust_weighted_sum(100, 20, 90, 80)
  UNION ALL SELECT 16, 'recalculate_seller_trust exists and is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'recalculate_seller_trust'
             AND p.prosecdef
         )
  UNION ALL SELECT 17, 'authenticated cannot execute recalculate_seller_trust',
         NOT has_function_privilege(
           'authenticated',
           'public.recalculate_seller_trust(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 18, 'trust guard checks maintain_trust before is_admin',
         strpos(
           pg_get_functiondef('public.enforce_users_column_guard()'::regprocedure),
           'maintain_trust'
         ) > 0
         AND strpos(
           pg_get_functiondef('public.enforce_users_column_guard()'::regprocedure),
           'maintain_trust'
         ) < strpos(
           pg_get_functiondef('public.enforce_users_column_guard()'::regprocedure),
           'is_admin()'
         )
  UNION ALL SELECT 19, 'users stores level, breakdown, and updated time',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'users'
             AND column_name = 'trust_level'
         )
         AND EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'users'
             AND column_name = 'trust_breakdown'
         )
         AND EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'users'
             AND column_name = 'trust_updated_at'
         )
  UNION ALL SELECT 20, 'public profile shows level and hides breakdown',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'user_public_profiles'
             AND column_name = 'trust_level'
         )
         AND NOT EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'user_public_profiles'
             AND column_name = 'trust_breakdown'
         )
  UNION ALL SELECT 22, 'review trust trigger is named after the rating trigger',
         (
           SELECT t.tgname
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'reviews'
             AND t.tgname = 'trg_reviews_rating_aggregate'
             AND NOT t.tgisinternal
         ) < (
           SELECT t.tgname
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'reviews'
             AND t.tgname = 'trg_reviews_trust_recalc'
             AND NOT t.tgisinternal
         )
  UNION ALL SELECT 21, 'verification, order, review, and report triggers exist',
         EXISTS (
           SELECT 1 FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'user_verifications'
             AND t.tgname = 'trg_user_verifications_seller_trust'
             AND NOT t.tgisinternal
         )
         AND EXISTS (
           SELECT 1 FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'orders'
             AND t.tgname = 'trg_orders_seller_trust'
             AND NOT t.tgisinternal
         )
         AND EXISTS (
           SELECT 1 FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'reviews'
             AND t.tgname = 'trg_reviews_trust_recalc'
             AND NOT t.tgisinternal
         )
         AND EXISTS (
           SELECT 1 FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'reports'
             AND t.tgname = 'trg_reports_seller_trust'
             AND NOT t.tgisinternal
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;

-- Direct writes, including from the SQL editor, must not stick.
-- A second recompute of the same seller must return the same total.
DO $$
DECLARE
  v_id uuid;
  v_score numeric;
  v_level text;
  v_breakdown jsonb;
  v_updated timestamptz;
  v_after numeric;
  v_first integer;
  v_second integer;
  v_seller uuid;
BEGIN
  SELECT u.user_id, u.trust_score, u.trust_level, u.trust_breakdown, u.trust_updated_at
    INTO v_id, v_score, v_level, v_breakdown, v_updated
  FROM public.users u
  ORDER BY u.user_id
  LIMIT 1;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'no users to test the trust guard';
  END IF;

  UPDATE public.users
  SET trust_score = CASE WHEN trust_score = 7 THEN 8 ELSE 7 END
  WHERE user_id = v_id;

  SELECT trust_score
    INTO v_after
  FROM public.users
  WHERE user_id = v_id;

  IF v_after IS DISTINCT FROM v_score THEN
    PERFORM set_config('thriftline.maintain_trust', '1', true);
    UPDATE public.users
    SET trust_score = v_score,
        trust_level = v_level,
        trust_breakdown = v_breakdown,
        trust_updated_at = v_updated
    WHERE user_id = v_id;
    PERFORM set_config('thriftline.maintain_trust', '0', true);
    RAISE EXCEPTION 'direct trust_score write was stored';
  END IF;

  SELECT sp.seller_id
    INTO v_seller
  FROM public.seller_profiles sp
  ORDER BY sp.seller_id
  LIMIT 1;

  IF v_seller IS NOT NULL THEN
    v_first := public.recalculate_seller_trust(v_seller);
    v_second := public.recalculate_seller_trust(v_seller);
    IF v_first IS DISTINCT FROM v_second THEN
      RAISE EXCEPTION 'duplicate recalculation drifted from % to %', v_first, v_second;
    END IF;
  END IF;
END
$$;
