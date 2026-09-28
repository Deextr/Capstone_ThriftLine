-- After 20260912010000_checkout_temp_delete.sql
SELECT
  CASE
    WHEN pg_get_functiondef('public.checkout_cart(uuid,uuid,integer)'::regprocedure)
         ILIKE '%DELETE FROM tmp_checkout_lines WHERE%'
    THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'checkout_cart clears temp lines with a WHERE clause' AS check_name;
