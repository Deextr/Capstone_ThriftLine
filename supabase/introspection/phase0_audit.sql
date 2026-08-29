-- ThriftLine — Phase 0 pre-migration audit.
--
-- READ-ONLY. Creates nothing, alters nothing, drops nothing.
-- Run the whole file in the Supabase SQL Editor and paste the single JSON
-- result back. It captures the facts that a plain column dump cannot:
-- NOT NULL constraints, defaults, RLS status, policies, triggers, functions,
-- indexes, and data-integrity counts.

SELECT jsonb_pretty(jsonb_build_object(

  -- Columns, with the nullability and defaults that decide whether
  -- handle_new_user can succeed.
  'columns', (
    SELECT jsonb_object_agg(t.table_name, t.cols)
    FROM (
      SELECT c.table_name,
             jsonb_agg(jsonb_build_object(
               'column',   c.column_name,
               'type',     c.data_type,
               'udt',      c.udt_name,
               'nullable', c.is_nullable,
               'default',  c.column_default
             ) ORDER BY c.ordinal_position) AS cols
      FROM information_schema.columns c
      JOIN information_schema.tables tb
        ON tb.table_schema = c.table_schema
       AND tb.table_name  = c.table_name
       AND tb.table_type  = 'BASE TABLE'
      WHERE c.table_schema = 'public'
      GROUP BY c.table_name
    ) t
  ),

  -- PK / FK / UNIQUE / CHECK. Reveals whether public.users.user_id actually
  -- references auth.users(id), and what ON DELETE behaviour is set.
  'constraints', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'table', rel.relname,
             'name',  con.conname,
             'type',  con.contype,
             'def',   pg_get_constraintdef(con.oid)
           ) ORDER BY rel.relname, con.conname), '[]'::jsonb)
    FROM pg_constraint con
    JOIN pg_class     rel ON rel.oid = con.conrelid
    JOIN pg_namespace ns  ON ns.oid  = rel.relnamespace
    WHERE ns.nspname = 'public'
  ),

  'enums', (
    SELECT coalesce(jsonb_object_agg(e.typname, e.vals), '{}'::jsonb)
    FROM (
      SELECT ty.typname,
             jsonb_agg(en.enumlabel ORDER BY en.enumsortorder) AS vals
      FROM pg_type ty
      JOIN pg_enum en ON en.enumtypid = ty.oid
      JOIN pg_namespace ns ON ns.oid = ty.typnamespace
      WHERE ns.nspname = 'public'
      GROUP BY ty.typname
    ) e
  ),

  -- Existing functions. If handle_new_user / is_admin already exist we
  -- reconcile rather than recreate.
  'functions', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'schema',           ns.nspname,
             'name',             p.proname,
             'args',             pg_get_function_identity_arguments(p.oid),
             'returns',          pg_get_function_result(p.oid),
             'security_definer', p.prosecdef,
             'language',         l.lanname
           ) ORDER BY ns.nspname, p.proname), '[]'::jsonb)
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_language  l  ON l.oid  = p.prolang
    WHERE ns.nspname IN ('public', 'auth')
      AND l.lanname <> 'internal'
  ),

  -- Includes auth schema so an existing handle_new_user trigger is visible.
  'triggers', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'schema',  ns.nspname,
             'table',   cl.relname,
             'trigger', tg.tgname,
             'def',     pg_get_triggerdef(tg.oid)
           ) ORDER BY ns.nspname, cl.relname, tg.tgname), '[]'::jsonb)
    FROM pg_trigger tg
    JOIN pg_class     cl ON cl.oid = tg.tgrelid
    JOIN pg_namespace ns ON ns.oid = cl.relnamespace
    WHERE NOT tg.tgisinternal
      AND ns.nspname IN ('public', 'auth')
  ),

  'rls_status', (
    SELECT coalesce(jsonb_object_agg(cl.relname, jsonb_build_object(
             'rls_enabled', cl.relrowsecurity,
             'rls_forced',  cl.relforcerowsecurity
           )), '{}'::jsonb)
    FROM pg_class cl
    JOIN pg_namespace ns ON ns.oid = cl.relnamespace
    WHERE ns.nspname = 'public' AND cl.relkind = 'r'
  ),

  'policies', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'table',  tablename,
             'policy', policyname,
             'cmd',    cmd,
             'permissive', permissive,
             'roles',  roles,
             'using',  qual,
             'check',  with_check
           ) ORDER BY tablename, policyname), '[]'::jsonb)
    FROM pg_policies
    WHERE schemaname = 'public'
  ),

  'indexes', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'table', tablename,
             'name',  indexname,
             'def',   indexdef
           ) ORDER BY tablename, indexname), '[]'::jsonb)
    FROM pg_indexes
    WHERE schemaname = 'public'
  ),

  -- Volume tells us how risky a destructive migration would be.
  'row_counts', jsonb_build_object(
    'auth_users',     (SELECT count(*) FROM auth.users),
    'public_users',   (SELECT count(*) FROM public.users),
    'products',       (SELECT count(*) FROM public.products),
    'product_images', (SELECT count(*) FROM public.product_images),
    'categories',     (SELECT count(*) FROM public.categories)
  ),

  -- Integrity probes. These decide whether we can safely add NOT NULL /
  -- UNIQUE / FK constraints without a backfill first.
  'integrity', jsonb_build_object(
    'auth_users_without_profile',
      (SELECT count(*) FROM auth.users a
         LEFT JOIN public.users u ON u.user_id = a.id
        WHERE u.user_id IS NULL),
    'profiles_without_auth_user',
      (SELECT count(*) FROM public.users u
         LEFT JOIN auth.users a ON a.id = u.user_id
        WHERE a.id IS NULL),
    'users_null_email',      (SELECT count(*) FROM public.users WHERE email IS NULL),
    'users_null_username',   (SELECT count(*) FROM public.users WHERE username IS NULL),
    'users_empty_username',  (SELECT count(*) FROM public.users WHERE username = ''),
    'users_null_full_name',  (SELECT count(*) FROM public.users WHERE full_name IS NULL),
    'products_orphan_seller',
      (SELECT count(*) FROM public.products p
         LEFT JOIN public.users u ON u.user_id = p.seller_id
        WHERE u.user_id IS NULL),
    'products_null_category',
      (SELECT count(*) FROM public.products WHERE category_id IS NULL),
    'product_images_orphan',
      (SELECT count(*) FROM public.product_images pi
         LEFT JOIN public.products p ON p.product_id = pi.product_id
        WHERE p.product_id IS NULL)
  ),

  -- Existing categories drive the idempotent seed strategy.
  'categories', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id',     category_id,
             'name',   category_name,
             'active', is_active
           ) ORDER BY category_name), '[]'::jsonb)
    FROM public.categories
  ),

  -- Which enum values are actually in use, so we know what a rename breaks.
  'value_distribution', jsonb_build_object(
    'user_role',      (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
                         FROM (SELECT role::text k, count(*) n
                                 FROM public.users GROUP BY 1) s),
    'account_status', (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
                         FROM (SELECT account_status::text k, count(*) n
                                 FROM public.users GROUP BY 1) s),
    'product_status', (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
                         FROM (SELECT status::text k, count(*) n
                                 FROM public.products GROUP BY 1) s),
    'listing_type',   (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
                         FROM (SELECT listing_type::text k, count(*) n
                                 FROM public.products GROUP BY 1) s),
    'condition',      (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
                         FROM (SELECT condition::text k, count(*) n
                                 FROM public.products GROUP BY 1) s)
  ),

  -- Storage buckets already in use (informs Phase 1, cheap to collect now).
  'storage_buckets', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', id, 'public', public
           ) ORDER BY id), '[]'::jsonb)
    FROM storage.buckets
  )

)) AS phase0_audit;
