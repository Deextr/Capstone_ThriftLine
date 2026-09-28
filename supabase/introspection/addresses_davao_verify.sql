-- Structural checks for Davao City buyer addresses.
-- Run after 20260911030000_addresses_davao_city.sql.

WITH checks AS (
  SELECT 1 AS seq, 'addresses_city_davao_check exists' AS check_name,
         EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'addresses_city_davao_check'
         ) AS ok
  UNION ALL SELECT 2, 'trg_addresses_davao_city exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_addresses_davao_city' AND NOT tgisinternal
         )
  UNION ALL SELECT 3, 'all address cities are Davao City',
         NOT EXISTS (
           SELECT 1 FROM public.addresses
           WHERE city IS DISTINCT FROM 'Davao City'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
