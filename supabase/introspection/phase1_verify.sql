-- ThriftLine — Phase 1 completion check.
--
-- READ-ONLY. Run AFTER applying all nine Phase 1 migrations.
-- Every row should report status 'PASS'.

WITH checks AS (

  SELECT 1 AS seq, 'users.is_phone_verified exists' AS check_name,
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'users'
            AND column_name = 'is_phone_verified') = 1 AS ok,
         '20260822010000' AS migration

  UNION ALL SELECT 2, 'seller_profiles table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'seller_profiles') = 1,
         '20260822020000'

  UNION ALL SELECT 3, 'user_verifications.liveness_passed exists',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'user_verifications'
            AND column_name = 'liveness_passed') = 1,
         '20260822030000'

  UNION ALL SELECT 4, 'one pending verification index exists',
         (SELECT count(*) FROM pg_indexes
          WHERE schemaname = 'public'
            AND indexname = 'user_verifications_one_pending_per_user') = 1,
         '20260822030000'

  UNION ALL SELECT 5, 'verification-docs bucket is private',
         (SELECT count(*) FROM storage.buckets
          WHERE id = 'verification-docs' AND public IS FALSE) = 1,
         '20260822040000'

  UNION ALL SELECT 6, 'user_settings table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'user_settings') = 1,
         '20260822050000'

  UNION ALL SELECT 7, 'addresses one-default index exists',
         (SELECT count(*) FROM pg_indexes
          WHERE schemaname = 'public'
            AND indexname = 'addresses_one_default_per_user') = 1,
         '20260822060000'

  UNION ALL SELECT 8, 'notifications table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'notifications') = 1,
         '20260822070000'

  UNION ALL SELECT 9, 'notify_user is security definer',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'notify_user'
            AND p.prosecdef) = 1,
         '20260822070000'

  UNION ALL SELECT 10, 'review_seller_verification exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'review_seller_verification'
            AND p.prosecdef) = 1,
         '20260822080000'

  UNION ALL SELECT 11, 'phone_otp_challenges table exists',
         (SELECT count(*) FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'phone_otp_challenges') = 1,
         '20260822090000'

  UNION ALL SELECT 12, 'authenticated cannot select OTP challenges',
         NOT has_table_privilege('authenticated', 'public.phone_otp_challenges', 'SELECT'),
         '20260822090000'

  UNION ALL SELECT 13, 'authenticated cannot insert notifications',
         NOT has_table_privilege('authenticated', 'public.notifications', 'INSERT'),
         '20260822070000'

)
SELECT
  seq,
  check_name,
  CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
  migration
FROM checks
ORDER BY seq;
