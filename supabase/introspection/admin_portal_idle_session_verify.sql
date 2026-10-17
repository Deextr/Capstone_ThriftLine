-- Verify admin portal idle session enforcement (run after 20261017230000 migration).

SELECT check_no, label, ok
FROM (
  SELECT 1 AS check_no,
         'admin_portal_sessions table exists' AS label,
         to_regclass('public.admin_portal_sessions') IS NOT NULL AS ok
  UNION ALL
  SELECT 2,
         'is_admin includes portal session helper',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = '_admin_portal_session_is_live'
         )
  UNION ALL
  SELECT 3,
         'admin_portal_session_begin granted to authenticated',
         has_function_privilege(
           'authenticated',
           'public.admin_portal_session_begin()',
           'EXECUTE'
         )
  UNION ALL
  SELECT 4,
         'financial_evidence delete policy exists',
         EXISTS (
           SELECT 1
           FROM pg_policies
           WHERE schemaname = 'storage'
             AND tablename = 'objects'
             AND policyname = 'financial_evidence_delete_admin'
         )
) checks
ORDER BY check_no;
