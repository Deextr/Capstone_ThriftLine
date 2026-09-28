-- Structural checks for Phase 5 orders. Every row should be PASS
-- after 20260911010000_phase5_orders.sql is applied.

WITH checks AS (
  SELECT 1 AS seq, 'orders table exists' AS check_name,
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'orders') = 1 AS ok
  UNION ALL SELECT 2, 'order_items table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'order_items') = 1
  UNION ALL SELECT 3, 'orders.order_number exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'orders'
             AND column_name = 'order_number'
         )
  UNION ALL SELECT 4, 'orders.auction_id unique index exists',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public' AND indexname = 'orders_auction_id_uidx'
         )
  UNION ALL SELECT 5, 'checkout_cart exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'checkout_cart') = 1
  UNION ALL SELECT 6, 'ensure_auction_order exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'ensure_auction_order') = 1
  UNION ALL SELECT 7, 'authenticated can EXECUTE checkout_cart',
         has_function_privilege(
           'authenticated',
           'public.checkout_cart(uuid, uuid, integer)',
           'EXECUTE'
         )
  UNION ALL SELECT 8, 'authenticated cannot INSERT orders',
         NOT has_table_privilege('authenticated', 'public.orders', 'INSERT')
  UNION ALL SELECT 9, 'authenticated cannot UPDATE orders',
         NOT has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  UNION ALL SELECT 10, 'authenticated cannot INSERT order_items',
         NOT has_table_privilege('authenticated', 'public.order_items', 'INSERT')
  UNION ALL SELECT 11, 'authenticated can SELECT orders',
         has_table_privilege('authenticated', 'public.orders', 'SELECT')
  UNION ALL SELECT 12, 'authenticated can EXECUTE set_order_address',
         has_function_privilege(
           'authenticated',
           'public.set_order_address(uuid, uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 13, 'close_auctions still exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'close_auctions') = 1
  UNION ALL SELECT 14, 'authenticated cannot EXECUTE ensure_auction_order',
         NOT has_function_privilege(
           'authenticated',
           'public.ensure_auction_order(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 15, 'authenticated cannot EXECUTE consume_product_stock',
         NOT has_function_privilege(
           'authenticated',
           'public.consume_product_stock(uuid, integer)',
           'EXECUTE'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
