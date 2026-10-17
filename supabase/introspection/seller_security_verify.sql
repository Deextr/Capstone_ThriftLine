-- Run after 20261017240000_seller_security_hardening.sql
-- Expect all PASS when applied on a database with that migration.

WITH checks AS (
  SELECT 1 AS seq,
         'authenticated cannot SELECT delivery_pin_hash column' AS check_name,
         NOT has_column_privilege(
           'authenticated',
           'public.shipments',
           'delivery_pin_hash',
           'SELECT'
         ) AS ok
  UNION ALL
  SELECT 2,
         'authenticated can SELECT shipment_id on shipments',
         has_column_privilege(
           'authenticated',
           'public.shipments',
           'shipment_id',
           'SELECT'
         )
  UNION ALL
  SELECT 3,
         'follows_select_authenticated policy removed',
         NOT EXISTS (
           SELECT 1
           FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'follows'
             AND policyname = 'follows_select_authenticated'
         )
  UNION ALL
  SELECT 4,
         'follows_select_own policy exists',
         EXISTS (
           SELECT 1
           FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'follows'
             AND policyname = 'follows_select_own'
         )
  UNION ALL
  SELECT 5,
         'products_price_positive constraint exists',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname = 'public'
             AND t.relname = 'products'
             AND c.conname = 'products_price_positive'
         )
  UNION ALL
  SELECT 6,
         'products_name_len constraint exists',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname = 'public'
             AND t.relname = 'products'
             AND c.conname = 'products_name_len'
         )
  UNION ALL
  SELECT 7,
         'verify_delivery_pin executable by authenticated',
         has_function_privilege(
           'authenticated',
           'public.verify_delivery_pin(uuid, text)',
           'EXECUTE'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
