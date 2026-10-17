-- DEV / TEST ONLY — prepare one order for another PayMongo claim attempt
-- (e.g. first claim failed with GCash; buyer wants to try bank on a new link).
--
-- What this does NOT do:
--   • Does not call PayMongo (no new claim link from SQL alone).
--   • Does not choose bank vs GCash (that is only on PayMongo's claim page).
--
-- What this DOES do:
--   • Shows current refund state for an order.
--   • Optionally unlocks + clears stale claim link so admin can "Retry PayMongo refund"
--     in the app, then buyer opens the NEW link and picks Bank account there.
--
-- Run in Supabase SQL Editor as a privileged role (postgres).
-- Replace the order number below before running Part 2.

-- =============================================================================
-- Part 1 — Inspect (always safe)
-- =============================================================================

-- >>> SET YOUR ORDER NUMBER HERE <<<
-- Example: 'TL-20261017-ABC'

SELECT
  o.order_number,
  o.order_status,
  p.payment_status,
  p.paymongo_channel,
  p.paymongo_payment_id,
  e.escrow_id,
  e.status AS escrow_status,
  e.refund_state,
  e.refund_provider_status,
  e.refund_provider_error,
  e.paymongo_refund_id,
  e.refund_lock_at IS NOT NULL AS refund_locked,
  e.refund_last_checked_at,
  e.refund_completed_at,
  d.transfer_link IS NOT NULL AS has_claim_link,
  d.transfer_link_expires_at,
  CASE
    WHEN d.transfer_link_expires_at IS NOT NULL
         AND d.transfer_link_expires_at < now() THEN true
    ELSE false
  END AS claim_link_expired,
  d.gcash_account_name IS NOT NULL AS buyer_gcash_on_file
FROM public.orders o
JOIN public.payments p ON p.order_id = o.order_id
LEFT JOIN public.escrow e ON e.order_id = o.order_id
LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
WHERE o.order_number = 'TL-261016-CA5F321D'
ORDER BY p.created_at DESC
LIMIT 1;

SELECT
  a.created_at,
  a.source,
  a.action,
  a.outcome,
  a.provider_status,
  a.error_code,
  a.has_transfer_link
FROM public.escrow_refund_attempts a
JOIN public.escrow e ON e.escrow_id = a.escrow_id
JOIN public.orders o ON o.order_id = e.order_id
WHERE o.order_number = 'TL-261016-CA5F321D'
ORDER BY a.created_at DESC
LIMIT 10;

-- =============================================================================
-- Part 1b — Try the SAME claim link again (no SQL change)
-- =============================================================================
-- If Part 1 shows:
--   refund_state = awaiting_buyer_claim
--   has_claim_link = true
--   claim_link_expired = false
-- then the buyer can open Transaction history → Open PayMongo claim link again
-- and choose Bank account (not GCash/G-Xchange) on PayMongo's page.
-- No Part 2 needed.

-- =============================================================================
-- Part 2 — Reset for a NEW PayMongo claim (run only if claim failed / expired)
-- =============================================================================
-- Uncomment the DO block, set v_order_number, run once, then:
--   1. Admin → order detail → Buyer refund → Retry PayMongo refund
--   2. Buyer → Transaction history → Open PayMongo claim link (new link)
--   3. On PayMongo page, choose Bank account and enter bank details

/*
DO $$
DECLARE
  v_order_number text := 'TL-261016-CA5F321D';
  v_escrow_id uuid;
  v_state public.escrow_refund_state_enum;
BEGIN
  SELECT e.escrow_id, e.refund_state
  INTO v_escrow_id, v_state
  FROM public.orders o
  JOIN public.escrow e ON e.order_id = o.order_id
  WHERE o.order_number = v_order_number
  FOR UPDATE OF e;

  IF v_escrow_id IS NULL THEN
    RAISE EXCEPTION 'No escrow row for order %', v_order_number;
  END IF;

  IF v_state IN (
    'succeeded'::public.escrow_refund_state_enum,
    'manual_completed'::public.escrow_refund_state_enum
  ) THEN
    RAISE EXCEPTION 'Refund already complete for %. Do not reset.', v_order_number;
  END IF;

  -- Unlock + mark as needing action so prepare_refund_retry accepts admin retry.
  UPDATE public.escrow
  SET refund_lock_at = NULL,
      refund_state = 'manual_required'::public.escrow_refund_state_enum,
      refund_provider_status = COALESCE(refund_provider_status, 'failed'),
      refund_provider_error = COALESCE(
        NULLIF(btrim(refund_provider_error), ''),
        'claim_failed_retry_with_bank'
      ),
      refund_last_checked_at = now(),
      refund_completed_at = NULL
  WHERE escrow_id = v_escrow_id
    AND status = 'refunded'::public.escrow_status_enum;

  -- Remove old claim link so the app does not reopen a dead GCash attempt.
  UPDATE public.escrow_refund_details
  SET transfer_link = NULL,
      transfer_link_expires_at = NULL
  WHERE escrow_id = v_escrow_id;

  -- Keep payment as paid until PayMongo or manual refund completes.
  UPDATE public.payments p
  SET payment_status = 'paid'::public.payment_status_enum
  FROM public.escrow e
  WHERE e.escrow_id = v_escrow_id
    AND p.payment_id = e.payment_id
    AND p.payment_status = 'refunded'::public.payment_status_enum
    AND EXISTS (
      SELECT 1 FROM public.escrow ex
      WHERE ex.escrow_id = v_escrow_id
        AND ex.refund_state IS DISTINCT FROM 'succeeded'::public.escrow_refund_state_enum
        AND ex.refund_state IS DISTINCT FROM 'manual_completed'::public.escrow_refund_state_enum
    );

  RAISE NOTICE 'Ready for admin Retry PayMongo refund on order % (escrow %).',
    v_order_number, v_escrow_id;
END $$;
*/

-- =============================================================================
-- Part 3 — Verify after Part 2 + admin Retry
-- =============================================================================

SELECT
  o.order_number,
  e.refund_state,
  e.refund_lock_at,
  d.transfer_link IS NOT NULL AS has_new_claim_link,
  d.transfer_link_expires_at,
  p.payment_status
FROM public.orders o
JOIN public.escrow e ON e.order_id = o.order_id
JOIN public.payments p ON p.payment_id = e.payment_id
LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
WHERE o.order_number = 'TL-261016-CA5F321D';
