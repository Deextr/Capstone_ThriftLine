-- Structural checks for Phase 8 reviews and community reports.
-- Run after 20260913020000_phase8_reviews_reports.sql.
-- Expect 20 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'reviews table exists' AS check_name,
         to_regclass('public.reviews') IS NOT NULL AS ok
  UNION ALL SELECT 2, 'reports table exists',
         to_regclass('public.reports') IS NOT NULL
  UNION ALL SELECT 3, 'report_evidence table exists',
         to_regclass('public.report_evidence') IS NOT NULL
  UNION ALL SELECT 4, 'reviews one-per-reviewer unique exists',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname = 'public'
             AND t.relname = 'reviews'
             AND c.conname = 'reviews_one_per_reviewer_per_order'
         )
  UNION ALL SELECT 5, 'authenticated cannot INSERT reviews',
         NOT has_table_privilege('authenticated', 'public.reviews', 'INSERT')
  UNION ALL SELECT 6, 'authenticated cannot UPDATE reviews',
         NOT has_table_privilege('authenticated', 'public.reviews', 'UPDATE')
  UNION ALL SELECT 7, 'authenticated cannot INSERT reports',
         NOT has_table_privilege('authenticated', 'public.reports', 'INSERT')
  UNION ALL SELECT 8, 'authenticated cannot UPDATE reports',
         NOT has_table_privilege('authenticated', 'public.reports', 'UPDATE')
  UNION ALL SELECT 9, 'authenticated cannot DELETE reports',
         NOT has_table_privilege('authenticated', 'public.reports', 'DELETE')
  UNION ALL SELECT 10, 'authenticated can EXECUTE submit_review',
         has_function_privilege(
           'authenticated',
           'public.submit_review(uuid, smallint, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 11, 'authenticated can EXECUTE update_review',
         has_function_privilege(
           'authenticated',
           'public.update_review(uuid, smallint, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 12, 'authenticated can EXECUTE submit_report',
         has_function_privilege(
           'authenticated',
           'public.submit_report(uuid, text, text, uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 13, 'authenticated can EXECUTE attach_report_evidence',
         has_function_privilege(
           'authenticated',
           'public.attach_report_evidence(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 14, 'authenticated cannot EXECUTE notify_user',
         NOT has_function_privilege(
           'authenticated',
           'public.notify_user(uuid, text, text, text, jsonb)',
           'EXECUTE'
         )
  UNION ALL SELECT 15, 'submit_review is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'submit_review'
             AND p.prosecdef
         )
  UNION ALL SELECT 16, 'submit_report is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'submit_report'
             AND p.prosecdef
         )
  UNION ALL SELECT 17, 'review rating aggregate trigger exists',
         EXISTS (
           SELECT 1
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'reviews'
             AND t.tgname = 'trg_reviews_rating_aggregate'
             AND NOT t.tgisinternal
         )
  UNION ALL SELECT 18, 'report decision notification trigger exists',
         EXISTS (
           SELECT 1
           FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'reports'
             AND t.tgname = 'trg_reports_notify_decision'
             AND NOT t.tgisinternal
         )
  UNION ALL SELECT 19, 'report-evidence bucket is private',
         EXISTS (
           SELECT 1
           FROM storage.buckets
           WHERE id = 'report-evidence'
             AND public IS FALSE
         )
  UNION ALL SELECT 20, 'reports default status is under_review',
         EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'reports'
             AND column_name = 'status'
             AND column_default ILIKE '%under_review%'
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
