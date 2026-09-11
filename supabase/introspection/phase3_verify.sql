-- Structural checks for Phase 3 auctions. Every row should be PASS
-- after 20260909030000_phase3_auctions.sql is applied.

WITH checks AS (
  SELECT 1 AS seq, 'auctions table exists' AS check_name,
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'auctions') = 1 AS ok
  UNION ALL SELECT 2, 'bids table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'bids') = 1
  UNION ALL SELECT 3, 'auctions.product_id is unique',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_attribute a
             ON a.attrelid = c.conrelid
            AND a.attnum = ANY (c.conkey)
           WHERE c.conrelid = 'public.auctions'::regclass
             AND c.contype = 'u'
             AND a.attname = 'product_id'
             AND array_length(c.conkey, 1) = 1
         )
  UNION ALL SELECT 4, 'place_bid exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'place_bid') = 1
  UNION ALL SELECT 5, 'close_auctions exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'close_auctions') = 1
  UNION ALL SELECT 6, 'ensure_product_auction exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'ensure_product_auction') = 1
  UNION ALL SELECT 7, 'v_user_bids exists',
         (SELECT count(*) FROM information_schema.views
          WHERE table_schema = 'public' AND table_name = 'v_user_bids') = 1
  UNION ALL SELECT 8, 'bids_insert_own policy is gone',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'bids'
            AND policyname IN ('bids_insert_own')) = 0
  UNION ALL SELECT 9, 'authenticated cannot INSERT bids',
         NOT has_table_privilege('authenticated', 'public.bids', 'INSERT')
  UNION ALL SELECT 10, 'authenticated cannot INSERT auctions',
         NOT has_table_privilege('authenticated', 'public.auctions', 'INSERT')
  UNION ALL SELECT 11, 'authenticated cannot UPDATE auctions',
         NOT has_table_privilege('authenticated', 'public.auctions', 'UPDATE')
  UNION ALL SELECT 12, 'authenticated can EXECUTE place_bid',
         has_function_privilege(
           'authenticated',
           'public.place_bid(uuid, numeric)',
           'EXECUTE'
         )
  UNION ALL SELECT 13, 'authenticated can EXECUTE close_auctions',
         has_function_privilege(
           'authenticated',
           'public.close_auctions()',
           'EXECUTE'
         )
  UNION ALL SELECT 14, 'hardcoded auction sync trigger is gone',
         (SELECT count(*) FROM pg_trigger
          WHERE tgname = 'trg_products_auction_sync' AND NOT tgisinternal) = 0
  UNION ALL SELECT 15, 'auctions and bids are in supabase_realtime',
         (SELECT count(*) FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND tablename IN ('auctions', 'bids')) = 2
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
