-- Structural checks for Phase 10 settlement.
-- Run after 20260914010000_phase10_settlement.sql.
-- Expect 22 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'escrow table exists' AS check_name,
         to_regclass('public.escrow') IS NOT NULL AS ok
  UNION ALL SELECT 2, 'seller_payouts table exists',
         to_regclass('public.seller_payouts') IS NOT NULL
  UNION ALL SELECT 3, 'report_appeals table exists',
         to_regclass('public.report_appeals') IS NOT NULL
  UNION ALL SELECT 4, 'escrow.order_id is unique',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname = 'public'
             AND t.relname = 'escrow'
             AND c.contype IN ('u', 'p')
             AND pg_get_constraintdef(c.oid) ILIKE '%order_id%'
         )
  UNION ALL SELECT 5, 'authenticated cannot INSERT escrow',
         NOT has_table_privilege('authenticated', 'public.escrow', 'INSERT')
  UNION ALL SELECT 6, 'authenticated cannot UPDATE escrow',
         NOT has_table_privilege('authenticated', 'public.escrow', 'UPDATE')
  UNION ALL SELECT 7, 'authenticated cannot INSERT seller_payouts',
         NOT has_table_privilege('authenticated', 'public.seller_payouts', 'INSERT')
  UNION ALL SELECT 8, 'authenticated cannot INSERT report_appeals',
         NOT has_table_privilege('authenticated', 'public.report_appeals', 'INSERT')
  UNION ALL SELECT 9, 'resolve_delivery_payment exists',
         to_regprocedure('public.resolve_delivery_payment(uuid, text, text)') IS NOT NULL
  UNION ALL SELECT 10, 'prepare_delivery_refund exists',
         to_regprocedure('public.prepare_delivery_refund(uuid, text)') IS NOT NULL
  UNION ALL SELECT 11, 'finalize_delivery_refund exists',
         to_regprocedure(
           'public.finalize_delivery_refund(uuid, text, text, text, text)'
         ) IS NOT NULL
  UNION ALL SELECT 12, 'seller_earnings_snapshot exists',
         to_regprocedure('public.seller_earnings_snapshot()') IS NOT NULL
  UNION ALL SELECT 13, 'request_seller_payout exists',
         to_regprocedure('public.request_seller_payout(integer)') IS NOT NULL
  UNION ALL SELECT 14, 'submit_report_appeal exists',
         to_regprocedure('public.submit_report_appeal(uuid, text)') IS NOT NULL
  UNION ALL SELECT 15, 'get_report_appeal_context exists',
         to_regprocedure('public.get_report_appeal_context(uuid)') IS NOT NULL
  UNION ALL SELECT 16, 'resolve_delivery_payment is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'resolve_delivery_payment'
             AND p.prosecdef
         )
  UNION ALL SELECT 17, 'authenticated can EXECUTE resolve_delivery_payment',
         has_function_privilege(
           'authenticated',
           'public.resolve_delivery_payment(uuid, text, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 18, 'anon cannot EXECUTE resolve_delivery_payment',
         NOT has_function_privilege(
           'anon',
           'public.resolve_delivery_payment(uuid, text, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 19, 'authenticated can SELECT escrow',
         has_table_privilege('authenticated', 'public.escrow', 'SELECT')
  UNION ALL SELECT 20, 'close_delivery_dispute still exists',
         to_regprocedure('public.close_delivery_dispute(uuid, text)') IS NOT NULL
  UNION ALL SELECT 21, 'decide_report still exists',
         to_regprocedure('public.decide_report(uuid, text, text)') IS NOT NULL
  UNION ALL SELECT 22, 'payments trigger creates escrow hold',
         EXISTS (
           SELECT 1
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'payments'
             AND t.tgname = 'trg_payments_ensure_escrow'
             AND NOT t.tgisinternal
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
