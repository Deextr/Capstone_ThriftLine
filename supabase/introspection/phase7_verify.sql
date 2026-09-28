-- Structural checks for Phase 7 freelance-rider delivery.
-- Run after 20260912030000_phase7_delivery.sql.
-- Expect 20 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'shipments table exists' AS check_name,
         to_regclass('public.shipments') IS NOT NULL AS ok
  UNION ALL SELECT 2, 'delivery_pin_secrets table exists',
         to_regclass('public.delivery_pin_secrets') IS NOT NULL
  UNION ALL SELECT 3, 'delivery_events table exists',
         to_regclass('public.delivery_events') IS NOT NULL
  UNION ALL SELECT 4, 'delivery_disputes table exists',
         to_regclass('public.delivery_disputes') IS NOT NULL
  UNION ALL SELECT 5, 'shipments.order_id is unique',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname = 'public'
             AND t.relname = 'shipments'
             AND c.contype = 'u'
             AND pg_get_constraintdef(c.oid) LIKE '%order_id%'
         )
  UNION ALL SELECT 6, 'authenticated cannot UPDATE shipments',
         NOT has_table_privilege('authenticated', 'public.shipments', 'UPDATE')
  UNION ALL SELECT 7, 'authenticated cannot INSERT shipments',
         NOT has_table_privilege('authenticated', 'public.shipments', 'INSERT')
  UNION ALL SELECT 8, 'authenticated cannot SELECT delivery_pin_secrets',
         NOT has_table_privilege(
           'authenticated',
           'public.delivery_pin_secrets',
           'SELECT'
         )
  UNION ALL SELECT 9, 'authenticated cannot EXECUTE ensure_paid_shipment',
         NOT has_function_privilege(
           'authenticated',
           'public.ensure_paid_shipment(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 10, 'authenticated can EXECUTE assign_freelance_rider',
         has_function_privilege(
           'authenticated',
           'public.assign_freelance_rider(uuid, text, text, text, text, timestamptz, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 11, 'authenticated can EXECUTE advance_delivery',
         has_function_privilege(
           'authenticated',
           'public.advance_delivery(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 12, 'authenticated can EXECUTE get_my_delivery_pin',
         has_function_privilege(
           'authenticated',
           'public.get_my_delivery_pin(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 13, 'authenticated can EXECUTE verify_delivery_pin',
         has_function_privilege(
           'authenticated',
           'public.verify_delivery_pin(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 14, 'authenticated can EXECUTE confirm_delivery',
         has_function_privilege(
           'authenticated',
           'public.confirm_delivery(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 15, 'authenticated can EXECUTE report_delivery_problem',
         has_function_privilege(
           'authenticated',
           'public.report_delivery_problem(uuid, text, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 16, 'authenticated can EXECUTE mark_delivery_failed',
         has_function_privilege(
           'authenticated',
           'public.mark_delivery_failed(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 17, 'authenticated can EXECUTE complete_expired_inspections',
         has_function_privilege(
           'authenticated',
           'public.complete_expired_inspections()',
           'EXECUTE'
         )
  UNION ALL SELECT 18, 'assign_freelance_rider is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'assign_freelance_rider'
             AND p.prosecdef
         )
  UNION ALL SELECT 19, 'paid-order shipment trigger exists',
         EXISTS (
           SELECT 1
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'orders'
             AND t.tgname = 'trg_orders_paid_ensure_shipment'
             AND NOT t.tgisinternal
         )
  UNION ALL SELECT 20, 'shipments in supabase_realtime',
         EXISTS (
           SELECT 1
           FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = 'shipments'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
