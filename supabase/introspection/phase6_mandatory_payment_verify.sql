-- Structural checks for the Phase 6 mandatory-payment revision.
-- Run after 20260912020000_mandatory_payment.sql.
-- Expect 16 PASS rows.

WITH checks AS (
  SELECT 1 AS seq, 'payments.paymongo_channel exists' AS check_name,
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'payments'
             AND column_name = 'paymongo_channel'
         ) AS ok
  UNION ALL SELECT 2, 'prepare_paymongo_checkout(uuid, text) exists',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'prepare_paymongo_checkout'
             AND oidvectortypes(p.proargtypes) = 'uuid, text'
         )
  UNION ALL SELECT 3, 'old prepare_paymongo_checkout(uuid) is gone',
         NOT EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'prepare_paymongo_checkout'
             AND pg_get_function_identity_arguments(p.oid) = 'p_order_id uuid'
         )
  UNION ALL SELECT 4, 'authenticated can EXECUTE prepare_paymongo_checkout(uuid, text)',
         has_function_privilege(
           'authenticated',
           'public.prepare_paymongo_checkout(uuid, text)',
           'EXECUTE'
         )
  UNION ALL SELECT 5, 'void_unpaid_checkout exists',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'void_unpaid_checkout') = 1
  UNION ALL SELECT 6, 'authenticated cannot EXECUTE void_unpaid_checkout',
         NOT has_function_privilege(
           'authenticated',
           'public.void_unpaid_checkout(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 7, 'authenticated can EXECUTE abandon_unpaid_checkout',
         has_function_privilege(
           'authenticated',
           'public.abandon_unpaid_checkout(uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 8, 'authenticated cannot EXECUTE restore_product_stock',
         NOT has_function_privilege(
           'authenticated',
           'public.restore_product_stock(uuid, integer)',
           'EXECUTE'
         )
  UNION ALL SELECT 9, 'authenticated cannot EXECUTE expire_unpaid_checkouts',
         NOT has_function_privilege(
           'authenticated',
           'public.expire_unpaid_checkouts()',
           'EXECUTE'
         )
  UNION ALL SELECT 10, 'authenticated cannot EXECUTE apply_paymongo_event',
         NOT has_function_privilege(
           'authenticated',
           'public.apply_paymongo_event(text, text, text, text, integer, text, uuid)',
           'EXECUTE'
         )
  UNION ALL SELECT 11, 'authenticated cannot UPDATE payments',
         NOT has_table_privilege('authenticated', 'public.payments', 'UPDATE')
  UNION ALL SELECT 12, 'authenticated cannot UPDATE orders',
         NOT has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  UNION ALL SELECT 13, 'void_unpaid_checkout is security definer',
         EXISTS (
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname = 'void_unpaid_checkout'
             AND p.prosecdef
         )
  UNION ALL SELECT 14, 'checkout_cart keeps one-seller reservation comment',
         pg_get_functiondef('public.checkout_cart(uuid,uuid,integer)'::regprocedure)
           LIKE '%One seller per payment session%'
  UNION ALL SELECT 15, 'checkout_cart still uses WHERE TRUE temp delete',
         pg_get_functiondef('public.checkout_cart(uuid,uuid,integer)'::regprocedure)
           LIKE '%DELETE FROM tmp_checkout_lines WHERE TRUE%'
  UNION ALL SELECT 16, 'apply_paymongo_event voids failed checkouts',
         pg_get_functiondef(
           'public.apply_paymongo_event(text,text,text,text,integer,text,uuid)'::regprocedure
         ) LIKE '%void_unpaid_checkout%'
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
