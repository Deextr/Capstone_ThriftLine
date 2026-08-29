-- ThriftLine — Phase 0 completion check.
--
-- READ-ONLY. Run AFTER applying all six migrations. Every row should report
-- status 'PASS'. Anything else names the migration that did not take effect.

WITH checks AS (

  SELECT 1 AS seq, 'is_admin hardened' AS check_name,
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'is_admin'
            AND p.prosecdef
            AND p.proconfig::text LIKE '%search_path%') = 1 AS ok,
         '20260818010000' AS migration

  UNION ALL SELECT 2, 'is_approved_seller exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'is_approved_seller'
            AND p.prosecdef) = 1,
         '20260818010000'

  UNION ALL SELECT 3, 'column guard trigger installed',
         (SELECT count(*) FROM pg_trigger
          WHERE tgname = 'trg_users_column_guard' AND NOT tgisinternal) = 1,
         '20260818020000'

  UNION ALL SELECT 4, 'users updated_at trigger installed',
         (SELECT count(*) FROM pg_trigger
          WHERE tgname = 'trg_users_updated_at' AND NOT tgisinternal) = 1,
         '20260818020000'

  UNION ALL SELECT 5, 'users.user_id default removed',
         (SELECT column_default FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'users'
            AND column_name = 'user_id') IS NULL,
         '20260818020000'

  UNION ALL SELECT 6, 'trust_score default is 80',
         (SELECT column_default FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'users'
            AND column_name = 'trust_score') LIKE '80%',
         '20260818020000'

  UNION ALL SELECT 7, 'no user still shows as Banned (<40)',
         (SELECT count(*) FROM public.users WHERE trust_score < 40) = 0,
         '20260818020000'

  UNION ALL SELECT 8, 'all 11 categories present',
         (SELECT count(*) FROM public.categories
          WHERE category_name IN ('Tops','Bottoms','Dresses','Outerwear','Shoes',
                                  'Bags','Accessories','Vintage','Streetwear',
                                  'Formal','Others')) = 11,
         '20260818030000'

  UNION ALL SELECT 9, 'no duplicate category names',
         (SELECT count(*) FROM (SELECT category_name FROM public.categories
                                GROUP BY category_name HAVING count(*) > 1) d) = 0,
         '20260818030000'

  UNION ALL SELECT 10, 'legacy users policies dropped',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'users'
            AND policyname IN ('Users can read own profile',
                               'Users can insert own profile',
                               'Users can update own profile',
                               'users_select_all',
                               'users_insert_self',
                               'users_update_self_admin')) = 0,
         '20260818040000'

  UNION ALL SELECT 11, 'users has no INSERT policy (trigger only)',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'users' AND cmd = 'INSERT') = 0,
         '20260818040000'

  UNION ALL SELECT 12, 'users SELECT is no longer USING (true)',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'users'
            AND cmd = 'SELECT' AND qual = 'true') = 0,
         '20260818040000'

  UNION ALL SELECT 13, 'product INSERT gated on is_approved_seller',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'products'
            AND cmd = 'INSERT' AND with_check LIKE '%is_approved_seller%') = 1,
         '20260818040000'

  UNION ALL SELECT 14, 'draft/removed products are not public',
         (SELECT count(*) FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'products'
            AND cmd = 'SELECT' AND qual = 'true') = 0,
         '20260818040000'

  UNION ALL SELECT 15, 'user_public_profiles view exists',
         (SELECT count(*) FROM information_schema.views
          WHERE table_schema = 'public' AND table_name = 'user_public_profiles') = 1,
         '20260818040000'

  UNION ALL SELECT 16, 'view is readable by anon and authenticated',
         (SELECT count(DISTINCT grantee) FROM information_schema.role_table_grants
          WHERE table_schema = 'public' AND table_name = 'user_public_profiles'
            AND privilege_type = 'SELECT'
            AND grantee IN ('anon','authenticated')) = 2,
         '20260818040000'

  UNION ALL SELECT 17, 'view hides email and phone_number',
         (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'user_public_profiles'
            AND column_name IN ('email','phone_number','account_status')) = 0,
         '20260818040000'

  UNION ALL SELECT 18, 'handle_new_auth_user has pinned search_path',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'handle_new_auth_user'
            AND p.prosecdef
            AND p.proconfig::text LIKE '%search_path%') = 1,
         '20260818050000'

  UNION ALL SELECT 19, 'signup trigger still attached to auth.users',
         (SELECT count(*) FROM pg_trigger
          WHERE tgname = 'on_auth_user_created' AND NOT tgisinternal) = 1,
         '20260818050000'

  UNION ALL SELECT 20, 'no orphaned profiles remain',
         (SELECT count(*) FROM public.users u
          WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.user_id)) = 0,
         '20260818060000'

  UNION ALL SELECT 21, 'users -> auth.users foreign key exists',
         (SELECT count(*) FROM pg_constraint
          WHERE conname = 'users_user_id_fkey' AND contype = 'f') = 1,
         '20260818060000'

  UNION ALL SELECT 22, 'every auth account has a profile',
         (SELECT count(*) FROM auth.users a
          WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.user_id = a.id)) = 0,
         'invariant'
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name,
       migration
FROM checks
ORDER BY seq;
