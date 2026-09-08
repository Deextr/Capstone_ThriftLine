-- Structural checks for Phase 2 catalog. Every row should be PASS
-- after 20260908010000_phase2_catalog.sql is applied.

WITH checks AS (
  SELECT 1 AS seq, 'products.name exists' AS check_name,
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'products'
            AND column_name = 'name') = 1 AS ok
  UNION ALL SELECT 2, 'products.quantity_available exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'products'
            AND column_name = 'quantity_available') = 1
  UNION ALL SELECT 3, 'products.search_vector exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'products'
            AND column_name = 'search_vector') = 1
  UNION ALL SELECT 4, 'products search GIN index exists',
         (SELECT count(*) FROM pg_indexes
          WHERE schemaname = 'public' AND indexname = 'products_search_vector_gin') = 1
  UNION ALL SELECT 5, 'increment_product_view exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'increment_product_view') = 1
  UNION ALL SELECT 6, 'follows table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'follows') = 1
  UNION ALL SELECT 7, 'follows RLS is forced',
         (SELECT c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'follows')
  UNION ALL SELECT 8, 'looking_for_posts.description exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'looking_for_posts'
            AND column_name = 'description') = 1
  UNION ALL SELECT 9, 'looking_for_posts.category_id exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'looking_for_posts'
            AND column_name = 'category_id') = 1
  UNION ALL SELECT 10, 'looking_for_posts.location exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'looking_for_posts'
            AND column_name = 'location') = 1
  UNION ALL SELECT 11, 'saved_items favorite trigger exists',
         (SELECT count(*) FROM pg_trigger
          WHERE tgname = 'trg_saved_items_favorite_count' AND NOT tgisinternal) = 1
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
