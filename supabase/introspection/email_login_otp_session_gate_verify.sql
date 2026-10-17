-- Verify XSYS-002 email login session gate migration (20261017260000).

SELECT 'email_login_session_gates table' AS check_name,
       EXISTS (
         SELECT 1
         FROM information_schema.tables
         WHERE table_schema = 'public'
           AND table_name = 'email_login_session_gates'
       ) AS ok;

SELECT 'auth_email_login_access_granted exists' AS check_name,
       EXISTS (
         SELECT 1
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'auth_email_login_access_granted'
       ) AS ok;

SELECT 'restrictive gate policy count' AS check_name,
       count(*)::int AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname = 'email_login_otp_restrictive';
