-- Verify late PayMongo payment reconciliation helpers exist (run after
-- 20261017190000_late_paymongo_payment_refund.sql).

SELECT
  CASE
    WHEN count(*) = 5 THEN 'PASS'
    ELSE 'FAIL'
  END AS late_paymongo_helpers,
  count(*) AS helper_count
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    '_paymongo_order_ineligible_for_fulfillment',
    '_late_paymongo_charge_centavos',
    '_capture_paymongo_payment_only',
    '_late_paymongo_refund_reason',
    '_reconcile_late_paymongo_success'
  );

SELECT
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'apply_paymongo_event'
    ) THEN 'PASS'
    ELSE 'FAIL'
  END AS apply_paymongo_event_exists;
