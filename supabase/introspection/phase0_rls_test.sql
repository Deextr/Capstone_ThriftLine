-- ThriftLine — Phase 0 behavioural RLS test (step 1 of 2: define).
--
-- Proves the policies actually enforce what they claim, rather than merely
-- existing. Impersonates real accounts by setting the same GUCs PostgREST sets
-- (`role` and `request.jwt.claims`), which is what auth.uid() and auth.role()
-- read.
--
-- ---------------------------------------------------------------------------
-- HOW TO RUN
-- ---------------------------------------------------------------------------
--   1. Run this file. It should report "Success. No rows returned."
--   2. Run phase0_rls_run.sql to execute the checks and see the results.
--
-- Two files, because the Supabase SQL Editor parses an entire script before it
-- executes any of it. A statement can therefore never reference an object that
-- an earlier statement in the same run creates — the object does not exist yet
-- at parse time, and the editor reports it as missing. Everything the checks
-- need lives inside this one function body, which is opaque at parse time.
--
-- ---------------------------------------------------------------------------
-- WHY THERE IS NO BEGIN/ROLLBACK
-- ---------------------------------------------------------------------------
-- An earlier version wrapped the checks in a transaction and rolled back. That
-- protection was illusory in this editor. Instead, every check that writes runs
-- inside its own plpgsql subtransaction which is *always* undone: on success the
-- block raises ZX001 to force the rollback and smuggles the observed result out
-- through the exception message. So the function mutates nothing, whether or not
-- the caller wraps it in a transaction.
--
-- Reading the results does not require any of this. The function is SECURITY
-- INVOKER on purpose: it must run with the caller's privileges and then drop to
-- authenticated/anon itself, never as a definer.

CREATE OR REPLACE FUNCTION public.phase0_rls_test()
-- `result` rather than `status`: an output column named status would shadow
-- products.status, which check 15 writes to.
RETURNS TABLE (
  seq        int,
  result     text,
  check_name text,
  expected   text,
  actual     text
)
LANGUAGE plpgsql
VOLATILE
AS $fn$
DECLARE
  v_log     jsonb := '[]'::jsonb;
  v_seller  uuid;
  v_buyer   uuid;
  v_admin   uuid;
  v_product uuid;
  v_actual  text;
  v_count   int;
BEGIN
  -- Identify test subjects while still running as the caller.
  SELECT u.user_id INTO v_seller FROM public.users u WHERE u.role = 'seller' ORDER BY u.created_at LIMIT 1;
  SELECT u.user_id INTO v_buyer  FROM public.users u WHERE u.role = 'buyer'  ORDER BY u.created_at LIMIT 1;
  SELECT u.user_id INTO v_admin  FROM public.users u WHERE u.role = 'admin'  ORDER BY u.created_at LIMIT 1;
  SELECT p.product_id INTO v_product FROM public.products p WHERE p.seller_id = v_seller LIMIT 1;

  IF v_seller IS NULL OR v_buyer IS NULL THEN
    RAISE EXCEPTION 'Need at least one seller and one buyer account to run these tests.';
  END IF;

  -- =========================================================================
  -- Acting as the BUYER
  -- =========================================================================
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_buyer, 'role', 'authenticated')::text,
                     true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  -- 1. A buyer must not be able to create a listing. This gate did not exist
  --    before 20260818040000.
  BEGIN
    INSERT INTO public.products (seller_id, name, condition, listing_type, price)
    VALUES (v_buyer, '__rls_probe__', 'good', 'fixed_price', 1);
    RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'allowed';
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'blocked';
  END;
  v_log := v_log || jsonb_build_object('seq', 1,
    'name', 'buyer cannot create a listing', 'expected', 'blocked', 'actual', v_actual);

  -- 2. A buyer must not be able to edit someone else's listing. RLS filters the
  --    row out rather than raising, so assert on the affected row count.
  IF v_product IS NOT NULL THEN
    BEGIN
      UPDATE public.products SET name = '__rls_probe__' WHERE product_id = v_product;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = v_count || ' rows';
    EXCEPTION
      WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
      WHEN OTHERS          THEN v_actual := 'error';
    END;
    v_log := v_log || jsonb_build_object('seq', 2,
      'name', 'buyer cannot edit another seller''s listing', 'expected', '0 rows', 'actual', v_actual);
  END IF;

  -- 3. Self-promotion to seller must be inert. The UPDATE itself succeeds (the
  --    user owns the row); trg_users_column_guard reverts the column.
  BEGIN
    UPDATE public.users SET role = 'seller' WHERE user_id = v_buyer;
    RAISE EXCEPTION USING ERRCODE = 'ZX001',
      MESSAGE = (SELECT u.role::text FROM public.users u WHERE u.user_id = v_buyer);
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'error';
  END;
  v_log := v_log || jsonb_build_object('seq', 3,
    'name', 'buyer cannot self-promote to seller', 'expected', 'buyer', 'actual', v_actual);

  -- 4. Trust score must not be self-assignable. Recorded as a verdict rather
  --    than a number so the comparison below stays uniform.
  BEGIN
    UPDATE public.users SET trust_score = 100 WHERE user_id = v_buyer;
    RAISE EXCEPTION USING ERRCODE = 'ZX001',
      MESSAGE = (SELECT u.trust_score::text FROM public.users u WHERE u.user_id = v_buyer);
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'error';
  END;
  v_log := v_log || jsonb_build_object('seq', 4,
    'name', 'buyer cannot inflate own trust_score', 'expected', 'not 100',
    'actual', CASE WHEN v_actual = '100' THEN '100' ELSE 'not 100' END);

  -- 5. Other users' rows, and therefore their email and phone, must be invisible.
  SELECT count(*) INTO v_count FROM public.users u WHERE u.user_id = v_seller;
  v_log := v_log || jsonb_build_object('seq', 5,
    'name', 'buyer cannot read another user''s row', 'expected', '0', 'actual', v_count::text);

  -- 6. Own row must still be readable, or the profile screen breaks.
  SELECT count(*) INTO v_count FROM public.users u WHERE u.user_id = v_buyer;
  v_log := v_log || jsonb_build_object('seq', 6,
    'name', 'buyer can read own row', 'expected', '1', 'actual', v_count::text);

  -- 7. The public view must expose other accounts, which is what
  --    checkUsernameAvailability() depends on.
  SELECT count(*) INTO v_count FROM public.user_public_profiles v WHERE v.user_id = v_seller;
  v_log := v_log || jsonb_build_object('seq', 7,
    'name', 'buyer can look up usernames via the view', 'expected', '1', 'actual', v_count::text);

  -- 8. The negative half of the admin tests below. Every admin-only policy in
  --    the database reduces to this one function, so a false positive here would
  --    quietly open all of them at once.
  v_log := v_log || jsonb_build_object('seq', 8,
    'name', 'is_admin() is false for a buyer', 'expected', 'false', 'actual', public.is_admin()::text);

  EXECUTE 'RESET ROLE';

  -- =========================================================================
  -- Acting as the SELLER
  -- =========================================================================
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_seller, 'role', 'authenticated')::text,
                     true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  -- 9. The approved seller must still be able to list. If this fails, Add
  --    Listing is broken in the app.
  BEGIN
    INSERT INTO public.products (seller_id, name, condition, listing_type, price)
    VALUES (v_seller, '__rls_probe__', 'good', 'fixed_price', 1);
    RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'allowed';
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'blocked';
  END;
  v_log := v_log || jsonb_build_object('seq', 9,
    'name', 'approved seller can create a listing', 'expected', 'allowed', 'actual', v_actual);

  -- 10. A seller must not be able to file a listing under another account.
  BEGIN
    INSERT INTO public.products (seller_id, name, condition, listing_type, price)
    VALUES (v_buyer, '__rls_probe__', 'good', 'fixed_price', 1);
    RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'allowed';
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'blocked';
  END;
  v_log := v_log || jsonb_build_object('seq', 10,
    'name', 'seller cannot list under another user''s id', 'expected', 'blocked', 'actual', v_actual);

  -- 11. Sellers must still see their own catalogue.
  SELECT count(*) INTO v_count FROM public.products p WHERE p.seller_id = v_seller;
  v_log := v_log || jsonb_build_object('seq', 11,
    'name', 'seller can read own listings', 'expected', '> 0',
    'actual', CASE WHEN v_count > 0 THEN '> 0' ELSE '0' END);

  EXECUTE 'RESET ROLE';

  -- =========================================================================
  -- Acting as the ADMIN
  --
  -- These are the moderation powers Phase 1 depends on: approving seller
  -- applications means writing another user's role, and handling reports means
  -- editing listings the admin does not own. Both are denied to everyone else,
  -- so they need positive proof that the admin exception actually works.
  --
  -- Skipped rather than failed when no admin exists, so the file still runs on a
  -- project where supabase/seed/001_role_assignments.sql has not been applied.
  -- =========================================================================
  IF v_admin IS NULL THEN
    v_log := v_log || jsonb_build_object('seq', 12,
      'name', 'admin checks', 'expected', 'run',
      'actual', 'SKIPPED — no admin account; see supabase/seed/001_role_assignments.sql');
  ELSE
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin, 'role', 'authenticated')::text,
                       true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- 12. The gate itself. Everything below is meaningless if this is wrong.
    v_log := v_log || jsonb_build_object('seq', 12,
      'name', 'is_admin() is true for an admin', 'expected', 'true', 'actual', public.is_admin()::text);

    -- 13. Moderation requires seeing accounts other than your own — the exact
    --     read that check 5 proves a buyer cannot perform.
    SELECT count(*) INTO v_count FROM public.users u WHERE u.user_id = v_buyer;
    v_log := v_log || jsonb_build_object('seq', 13,
      'name', 'admin can read another user''s row', 'expected', '1', 'actual', v_count::text);

    -- 14. Approving a seller application is a role write by someone other than
    --     the row owner. trg_users_column_guard must let this through, having
    --     reverted the identical statement in check 3.
    BEGIN
      UPDATE public.users SET role = 'seller' WHERE user_id = v_buyer;
      RAISE EXCEPTION USING ERRCODE = 'ZX001',
        MESSAGE = (SELECT u.role::text FROM public.users u WHERE u.user_id = v_buyer);
    EXCEPTION
      WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
      WHEN OTHERS          THEN v_actual := 'error';
    END;
    v_log := v_log || jsonb_build_object('seq', 14,
      'name', 'admin can promote a buyer to seller', 'expected', 'seller', 'actual', v_actual);

    -- 15. Report handling means taking down listings owned by other people.
    IF v_product IS NOT NULL THEN
      BEGIN
        UPDATE public.products SET status = 'removed' WHERE product_id = v_product;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = v_count || ' rows';
      EXCEPTION
        WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
        WHEN OTHERS          THEN v_actual := 'error';
      END;
    ELSE
      v_actual := 'SKIPPED — the seed seller has no listings';
    END IF;
    v_log := v_log || jsonb_build_object('seq', 15,
      'name', 'admin can moderate another seller''s listing', 'expected', '1 rows', 'actual', v_actual);

    -- 16. Category management is admin-only writes on an otherwise public table.
    BEGIN
      INSERT INTO public.categories (category_name, is_active) VALUES ('__rls_probe__', false);
      RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'allowed';
    EXCEPTION
      WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
      WHEN OTHERS          THEN v_actual := 'blocked';
    END;
    v_log := v_log || jsonb_build_object('seq', 16,
      'name', 'admin can create a category', 'expected', 'allowed', 'actual', v_actual);

    EXECUTE 'RESET ROLE';
  END IF;

  -- =========================================================================
  -- Acting as ANON
  -- =========================================================================
  PERFORM set_config('request.jwt.claims', '', true);
  EXECUTE 'SET LOCAL ROLE anon';

  -- 17. The original leak: users_select_all USING (true) exposed every column
  --     of every account to anyone holding the anon key.
  SELECT count(*) INTO v_count FROM public.users;
  v_log := v_log || jsonb_build_object('seq', 17,
    'name', 'anon cannot read the users table', 'expected', '0', 'actual', v_count::text);

  -- 18. Categories stay public so the listing form can populate before login.
  SELECT count(*) INTO v_count FROM public.categories;
  v_log := v_log || jsonb_build_object('seq', 18,
    'name', 'anon can read categories', 'expected', '> 0',
    'actual', CASE WHEN v_count > 0 THEN '> 0' ELSE '0' END);

  -- 19. The mirror of check 16 — writes on that same public table must be closed.
  BEGIN
    INSERT INTO public.categories (category_name, is_active) VALUES ('__rls_probe_anon__', false);
    RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'allowed';
  EXCEPTION
    WHEN SQLSTATE 'ZX001' THEN v_actual := SQLERRM;
    WHEN OTHERS          THEN v_actual := 'blocked';
  END;
  v_log := v_log || jsonb_build_object('seq', 19,
    'name', 'anon cannot create a category', 'expected', 'blocked', 'actual', v_actual);

  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);

  RETURN QUERY
  SELECT (e->>'seq')::int,
         CASE
           WHEN e->>'actual' LIKE 'SKIPPED%'    THEN 'SKIP'
           WHEN e->>'expected' = e->>'actual'   THEN 'PASS'
           ELSE 'FAIL'
         END,
         e->>'name',
         e->>'expected',
         e->>'actual'
  FROM jsonb_array_elements(v_log) AS e
  ORDER BY (e->>'seq')::int;
END;
$fn$;

COMMENT ON FUNCTION public.phase0_rls_test() IS
  'Phase 0 behavioural RLS check. Writes nothing: every mutating probe runs in a subtransaction that is always rolled back. Drop it once Phase 0 is signed off.';
