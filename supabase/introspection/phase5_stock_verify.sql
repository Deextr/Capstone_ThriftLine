-- Structural checks for listing stock. Every row should be PASS
-- after 20260911020000_listing_stock.sql is applied.

WITH checks AS (
  SELECT 1 AS seq, 'products.quantity_available exists' AS check_name,
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'products'
             AND column_name = 'quantity_available'
         ) AS ok
  UNION ALL SELECT 2, 'products_auction_quantity_check exists',
         EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'products_auction_quantity_check'
         )
  UNION ALL SELECT 3, 'trg_products_auction_stock exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_products_auction_stock' AND NOT tgisinternal
         )
  UNION ALL SELECT 4, 'trg_cart_items_stock exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_cart_items_stock' AND NOT tgisinternal
         )
  UNION ALL SELECT 5, 'max_purchasable_quantity exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'max_purchasable_quantity') = 1
  UNION ALL SELECT 6, 'auction max purchasable is 1 when stock is 5',
         public.max_purchasable_quantity('auction'::listing_type_enum, 5) = 1
  UNION ALL SELECT 7, 'fixed-price max purchasable follows stock',
         public.max_purchasable_quantity('fixed_price'::listing_type_enum, 5) = 5
  UNION ALL SELECT 8, 'sold listing max purchasable is 0',
         public.max_purchasable_quantity('fixed_price'::listing_type_enum, 0) = 0
  UNION ALL SELECT 9, 'checkout_cart still exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'checkout_cart') = 1
  UNION ALL SELECT 10, 'consume_product_stock still exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'consume_product_stock') = 1
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
