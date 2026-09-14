-- Structural checks for Phase 6 PayMongo. Run after
-- 20260911040000_phase6_paymongo_enum.sql, 20260911040100_phase6_paymongo.sql,
-- and 20260912020000_mandatory_payment.sql (prepare signature is uuid, text).
-- Expect 16 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'payment_method_enum has paymongo' AS check_name,
         EXISTS (
           SELECT 1
           FROM pg_enum e
           JOIN pg_type t ON t.oid = e.enumtypid
           JOIN pg_namespace n ON n.oid = t.typnamespace
           WHERE n.nspname = 'public'
             AND t.typname = 'payment_method_enum'
             AND e.enumlabel = 'paymongo'
         ) AS ok
  UNION ALL SELECT 2, 'payments.checkout_session_id exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'payments'
             AND column_name = 'checkout_session_id'
         )
  UNION ALL SELECT 3, 'payments.amount_centavos exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'payments'
             AND column_name = 'amount_centavos'
         )
  UNION ALL SELECT 4, 'one paid payment per order index',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public'
             AND indexname = 'payments_one_paid_per_order'
         )
  UNION ALL SELECT 5, 'one pending payment per order index',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public'
             AND indexname = 'payments_one_pending_per_order'
         )
  UNION ALL SELECT 6, 'prepare_paymongo_checkout exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'prepare_paymongo_checkout') = 1
  UNION ALL SELECT 7, 'attach_paymongo_checkout exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'attach_paymongo_checkout') = 1
  UNION ALL SELECT 8, 'apply_paymongo_event exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'apply_paymongo_event') = 1
  UNION ALL SELECT 9, 'authenticated can EXECUTE prepare_paymongo_checkout',
         has_function_privilege(
           'authenticated',
           'public.prepare_paymongo_checkout(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 10, 'authenticated cannot EXECUTE apply_paymongo_event',
         NOT has_function_privilege(
           'authenticated',
           'public.apply_paymongo_event(text, text, text, text, integer, text, uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 11, 'authenticated cannot INSERT payments',
         NOT has_table_privilege('authenticated', 'public.payments', 'INSERT')
  UNION ALL SELECT 12, 'authenticated cannot UPDATE payments',
         NOT has_table_privilege('authenticated', 'public.payments', 'UPDATE')
  UNION ALL SELECT 13, 'authenticated cannot UPDATE orders',
         NOT has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  UNION ALL SELECT 14, 'paymongo_webhook_events exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'paymongo_webhook_events') = 1
  UNION ALL SELECT 15, 'orders in supabase_realtime',
         EXISTS (
           SELECT 1 FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND tablename = 'orders'
         )
  UNION ALL SELECT 16, 'authenticated cannot EXECUTE attach_paymongo_checkout',
         NOT has_function_privilege(
           'authenticated',
           'public.attach_paymongo_checkout(uuid, text, text, uuid)',
           'EXECUTE'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
