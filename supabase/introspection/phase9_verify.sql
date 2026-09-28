-- Structural checks for Phase 9 Admin Review Center.
-- Run after 20260913030000_phase9_admin_review.sql.
-- Expect 16 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'decide_report exists' AS check_name,
         to_regprocedure('public.decide_report(uuid, text, text)') IS NOT NULL AS ok
  UNION ALL SELECT 2, 'close_delivery_dispute exists',
         to_regprocedure('public.close_delivery_dispute(uuid, text)') IS NOT NULL
  UNION ALL SELECT 3, 'decide_report is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'decide_report'
             AND p.prosecdef
         )
  UNION ALL SELECT 4, 'close_delivery_dispute is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'close_delivery_dispute'
             AND p.prosecdef
         )
  UNION ALL SELECT 5, 'authenticated can EXECUTE decide_report',
         has_function_privilege(
           'authenticated',
           'public.decide_report(uuid, text, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 6, 'authenticated can EXECUTE close_delivery_dispute',
         has_function_privilege(
           'authenticated',
           'public.close_delivery_dispute(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 7, 'authenticated cannot UPDATE reports',
         NOT has_table_privilege('authenticated', 'public.reports', 'UPDATE')
  UNION ALL SELECT 8, 'authenticated cannot UPDATE delivery_disputes',
         NOT has_table_privilege(
           'authenticated',
           'public.delivery_disputes',
           'UPDATE'
         )
  UNION ALL SELECT 9, 'authenticated cannot INSERT reports',
         NOT has_table_privilege('authenticated', 'public.reports', 'INSERT')
  UNION ALL SELECT 10, 'authenticated cannot INSERT delivery_disputes',
         NOT has_table_privilege(
           'authenticated',
           'public.delivery_disputes',
           'INSERT'
         )
  UNION ALL SELECT 11, 'delivery_disputes.admin_note exists',
         EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'delivery_disputes'
             AND column_name = 'admin_note'
         )
  UNION ALL SELECT 12, 'delivery_disputes.reviewed_by exists',
         EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'delivery_disputes'
             AND column_name = 'reviewed_by'
         )
  UNION ALL SELECT 13, 'delivery_disputes.resolved_at exists',
         EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'delivery_disputes'
             AND column_name = 'resolved_at'
         )
  UNION ALL SELECT 14, 'report-evidence bucket is still private',
         EXISTS (
           SELECT 1
           FROM storage.buckets
           WHERE id = 'report-evidence'
             AND public IS FALSE
         )
  UNION ALL SELECT 15, 'anon cannot EXECUTE decide_report',
         NOT has_function_privilege(
           'anon',
           'public.decide_report(uuid, text, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 16, 'review_seller_verification still exists',
         to_regprocedure(
           'public.review_seller_verification(uuid, text, text)'
         ) IS NOT NULL
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
