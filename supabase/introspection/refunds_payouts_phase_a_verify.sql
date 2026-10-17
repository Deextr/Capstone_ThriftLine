-- Structural checks for buyer refunds and Phase A seller payouts.
-- Run after:
--   20261016140000_qrph_only_checkout.sql
--   20261016150000_refund_tracking.sql
--   20261016155900_seller_payout_status_values.sql (run alone)
--   20261016160000_seller_payout_manual_transfer.sql
-- Read only. Expect 41 PASS rows.

WITH checks AS (
  -- QR Ph checkout
  SELECT 1 AS seq, 'payments channel constraint accepts qrph' AS check_name,
         EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'payments_paymongo_channel_chk'
             AND pg_get_constraintdef(oid) ILIKE '%qrph%'
         ) AS ok
  UNION ALL SELECT 2, 'prepare_paymongo_checkout exists',
         to_regprocedure('public.prepare_paymongo_checkout(uuid, text, uuid)') IS NOT NULL

  -- Refund tracking schema
  UNION ALL SELECT 3, 'escrow_refund_state_enum has 5 values',
         (SELECT count(*) FROM pg_enum e
            JOIN pg_type t ON t.oid = e.enumtypid
           WHERE t.typname = 'escrow_refund_state_enum') = 5
  UNION ALL SELECT 4, 'escrow.refund_state column exists',
         EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'escrow'
                   AND column_name = 'refund_state')
  UNION ALL SELECT 5, 'escrow.refund_completed_at column exists',
         EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'escrow'
                   AND column_name = 'refund_completed_at')
  UNION ALL SELECT 6, 'refunded escrow must have a refund_state',
         EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'escrow_refunded_has_state_chk')
  UNION ALL SELECT 7, 'no refunded escrow is missing refund_state',
         NOT EXISTS (SELECT 1 FROM public.escrow
                     WHERE status = 'refunded' AND refund_state IS NULL)
  UNION ALL SELECT 8, 'payment is refunded only when the refund is complete',
         NOT EXISTS (
           SELECT 1 FROM public.escrow e
           JOIN public.payments p ON p.payment_id = e.payment_id
           WHERE p.payment_status = 'refunded'
             AND e.status = 'refunded'
             AND e.refund_state NOT IN ('succeeded', 'manual_completed')
         )
  UNION ALL SELECT 9, 'escrow_refund_details table exists',
         to_regclass('public.escrow_refund_details') IS NOT NULL
  UNION ALL SELECT 10, 'escrow_refund_attempts table exists',
         to_regclass('public.escrow_refund_attempts') IS NOT NULL
  UNION ALL SELECT 11, 'escrow_refund_details has RLS forced',
         (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
           WHERE oid = 'public.escrow_refund_details'::regclass)
  UNION ALL SELECT 12, 'escrow_refund_attempts has RLS forced',
         (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
           WHERE oid = 'public.escrow_refund_attempts'::regclass)
  UNION ALL SELECT 13, 'authenticated cannot write escrow_refund_details',
         NOT has_table_privilege('authenticated', 'public.escrow_refund_details', 'INSERT')
         AND NOT has_table_privilege('authenticated', 'public.escrow_refund_details', 'UPDATE')
  UNION ALL SELECT 14, 'authenticated cannot write escrow_refund_attempts',
         NOT has_table_privilege('authenticated', 'public.escrow_refund_attempts', 'INSERT')
         AND NOT has_table_privilege('authenticated', 'public.escrow_refund_attempts', 'UPDATE')
  UNION ALL SELECT 15, 'authenticated still cannot UPDATE escrow',
         NOT has_table_privilege('authenticated', 'public.escrow', 'UPDATE')

  -- Refund RPCs
  UNION ALL SELECT 16, 'finalize_delivery_refund has transfer link params',
         to_regprocedure(
           'public.finalize_delivery_refund(uuid, text, text, text, text, text, timestamptz, text)'
         ) IS NOT NULL
  UNION ALL SELECT 17, 'finalize_fulfillment_sla_refund is service-only',
         to_regprocedure(
           'public.finalize_fulfillment_sla_refund(uuid, text, text, text, text, timestamptz, text)'
         ) IS NOT NULL
         AND NOT has_function_privilege(
           'authenticated',
           'public.finalize_fulfillment_sla_refund(uuid, text, text, text, text, timestamptz, text)',
           'EXECUTE')
  UNION ALL SELECT 18, 'record_refund_attempt exists',
         to_regprocedure(
           'public.record_refund_attempt(uuid, text, text, text, text, integer, text, text, boolean)'
         ) IS NOT NULL
  UNION ALL SELECT 19, 'apply_refund_provider_update exists',
         to_regprocedure(
           'public.apply_refund_provider_update(text, text, text, timestamptz, text)'
         ) IS NOT NULL
  UNION ALL SELECT 20, 'prepare_refund_retry exists',
         to_regprocedure('public.prepare_refund_retry(uuid)') IS NOT NULL
  UNION ALL SELECT 21, 'apply_refund_retry_result exists',
         to_regprocedure(
           'public.apply_refund_retry_result(uuid, text, text, text, text, timestamptz, text)'
         ) IS NOT NULL
  UNION ALL SELECT 22, 'clear_unverified_refund_lock exists',
         to_regprocedure('public.clear_unverified_refund_lock(uuid)') IS NOT NULL
  UNION ALL SELECT 23, 'list_refunds_to_reconcile is service-only',
         to_regprocedure('public.list_refunds_to_reconcile(integer)') IS NOT NULL
         AND NOT has_function_privilege(
           'authenticated', 'public.list_refunds_to_reconcile(integer)', 'EXECUTE')
  UNION ALL SELECT 24, 'submit_my_refund_gcash exists',
         to_regprocedure('public.submit_my_refund_gcash(uuid, text, text)') IS NOT NULL
  UNION ALL SELECT 25, 'admin_record_manual_refund exists',
         to_regprocedure(
           'public.admin_record_manual_refund(uuid, integer, text, timestamptz, text, text, text, text)'
         ) IS NOT NULL
  UNION ALL SELECT 26, 'anon cannot record a manual refund',
         NOT has_function_privilege(
           'anon',
           'public.admin_record_manual_refund(uuid, integer, text, timestamptz, text, text, text, text)',
           'EXECUTE')
  UNION ALL SELECT 27, 'refund RPCs are security definer',
         (SELECT bool_and(p.prosecdef) FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proname IN (
               'record_refund_attempt', 'apply_refund_provider_update',
               'prepare_refund_retry', 'apply_refund_retry_result',
               'clear_unverified_refund_lock', 'submit_my_refund_gcash',
               'admin_record_manual_refund'))

  -- Seller payouts (Phase A, manual transfer)
  UNION ALL SELECT 28, 'payout enum has paid, rejected, cancelled',
         (SELECT count(*) FROM pg_enum e
            JOIN pg_type t ON t.oid = e.enumtypid
           WHERE t.typname = 'seller_payout_status_enum'
             AND e.enumlabel IN ('paid', 'rejected', 'cancelled')) = 3
  UNION ALL SELECT 29, 'seller_payouts transfer columns exist',
         (SELECT count(*) FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'seller_payouts'
             AND column_name IN ('transferred_amount_centavos', 'gcash_reference',
                                 'transferred_at', 'evidence_path',
                                 'processed_by', 'processed_at')) = 6
  UNION ALL SELECT 30, 'paid payout requires a full transfer record',
         EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'seller_payouts_paid_record_chk'
                   AND pg_get_constraintdef(oid) ILIKE '%evidence_path%')
  UNION ALL SELECT 31, 'one open payout request per seller',
         to_regclass('public.seller_payouts_one_open_request_uidx') IS NOT NULL
  UNION ALL SELECT 32, 'authenticated cannot write seller_payouts directly',
         NOT has_table_privilege('authenticated', 'public.seller_payouts', 'INSERT')
         AND NOT has_table_privilege('authenticated', 'public.seller_payouts', 'UPDATE')
  UNION ALL SELECT 33, 'cancel_my_seller_payout exists',
         to_regprocedure('public.cancel_my_seller_payout(uuid)') IS NOT NULL
  UNION ALL SELECT 34, 'admin_list_seller_payouts exists',
         to_regprocedure('public.admin_list_seller_payouts(text, text, integer, integer)') IS NOT NULL
  UNION ALL SELECT 35, 'admin_list_buyer_refunds exists',
         to_regprocedure('public.admin_list_buyer_refunds(text, text, integer, integer)') IS NOT NULL
  UNION ALL SELECT 35, 'admin_mark_seller_payout_paid exists',
         to_regprocedure(
           'public.admin_mark_seller_payout_paid(uuid, integer, text, timestamptz, text, text)'
         ) IS NOT NULL
  UNION ALL SELECT 36, 'admin_reject_seller_payout exists',
         to_regprocedure('public.admin_reject_seller_payout(uuid, text)') IS NOT NULL
  UNION ALL SELECT 37, 'anon cannot mark a payout paid',
         NOT has_function_privilege(
           'anon',
           'public.admin_mark_seller_payout_paid(uuid, integer, text, timestamptz, text, text)',
           'EXECUTE')

  -- Private evidence storage
  UNION ALL SELECT 38, 'financial-evidence bucket is private',
         EXISTS (SELECT 1 FROM storage.buckets
                 WHERE id = 'financial-evidence' AND public = false)
  UNION ALL SELECT 39, 'financial-evidence insert is admin only',
         EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'storage' AND tablename = 'objects'
                   AND policyname = 'financial_evidence_insert_admin')
  UNION ALL SELECT 40, 'financial-evidence read is admin only',
         EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'storage' AND tablename = 'objects'
                   AND policyname = 'financial_evidence_select_admin')
  UNION ALL SELECT 41, 'financial-evidence delete is admin only',
         EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'storage' AND tablename = 'objects'
                   AND policyname = 'financial_evidence_delete_admin')
  UNION ALL SELECT 42, 'release is blocked after an unconfirmed refund',
         EXISTS (
           SELECT 1 FROM pg_trigger t
           JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.oid = 'public.escrow'::regclass
             AND t.tgname = 'trg_escrow_guard_unconfirmed_refund'
             AND NOT t.tgisinternal
         )
)
SELECT seq,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS status,
       check_name
FROM checks
ORDER BY seq;
