-- DEV / TEST ONLY — finish a successful delivery by skipping the inspection wait.
--
-- Uses the same path as the app: expire inspection → complete_expired_inspections()
-- → order completed → escrow auto-release (if paid, no open dispute).
--
-- Prerequisites (check Part 1):
--   • delivery_status = inspection_period
--   • delivery_verified_at IS NOT NULL (buyer already verified with Delivery PIN)
--   • No open delivery_disputes on this order
--
-- Run in Supabase SQL Editor as postgres (or any role that can UPDATE + call RPC).

-- =============================================================================
-- Part 1 — Inspect (always safe) — TL-261017-DC4116C2
-- =============================================================================

SELECT
  o.order_id,
  o.order_number,
  o.order_status,
  p.payment_status,
  e.status AS escrow_status,
  s.shipment_id,
  s.delivery_status,
  s.delivery_verified_at,
  s.inspection_started_at,
  s.inspection_expires_at,
  s.inspection_expires_at <= now() AS inspection_already_expired,
  s.buyer_confirmed_received,
  s.buyer_confirmed_received_at,
  s.completed_at AS shipment_completed_at,
  (
    SELECT COUNT(*)
    FROM public.delivery_disputes d
    WHERE d.order_id = o.order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) AS open_delivery_disputes
FROM public.orders o
LEFT JOIN public.payments p ON p.order_id = o.order_id
LEFT JOIN public.escrow e ON e.order_id = o.order_id
LEFT JOIN public.shipments s ON s.order_id = o.order_id
WHERE o.order_number = 'TL-261017-DC4116C2';

-- If delivery_status is NOT inspection_period, do not run Part 2 yet.
-- Complete delivery in the app (seller ships → rider delivers → buyer PIN) first.

-- =============================================================================
-- Part 2 — Expire inspection window for this order (run once)
-- =============================================================================

/*
DO $$
DECLARE
  v_order_number text := 'TL-261017-DC4116C2';
  v_order_id uuid;
  v_shipment_id uuid;
BEGIN
  SELECT o.order_id, s.shipment_id
  INTO v_order_id, v_shipment_id
  FROM public.orders o
  JOIN public.shipments s ON s.order_id = o.order_id
  WHERE o.order_number = v_order_number
  FOR UPDATE OF s;

  IF v_order_id IS NULL OR v_shipment_id IS NULL THEN
    RAISE EXCEPTION 'No shipment for order %', v_order_number;
  END IF;

  UPDATE public.shipments
  SET
    inspection_expires_at = now() - interval '1 minute',
    buyer_confirmed_received = true,
    buyer_confirmed_received_at = COALESCE(buyer_confirmed_received_at, now())
  WHERE shipment_id = v_shipment_id
    AND delivery_status = 'inspection_period'::public.delivery_status_enum
    AND delivery_verified_at IS NOT NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Shipment not in inspection_period with verified delivery for %. See Part 1.',
      v_order_number;
  END IF;

  RAISE NOTICE 'Inspection expired for %. Run Part 3 next.', v_order_number;
END $$;
*/

-- =============================================================================
-- Part 3 — Auto-complete (same RPC the buyer/seller apps call)
-- =============================================================================

-- SELECT public.complete_expired_inspections() AS orders_completed;

-- =============================================================================
-- Part 4 — Verify successful delivery
-- =============================================================================

SELECT
  o.order_number,
  o.order_status,
  s.delivery_status,
  s.auto_completed,
  s.completion_reason,
  s.completed_at,
  e.status AS escrow_status,
  e.released_at,
  p.payment_status
FROM public.orders o
LEFT JOIN public.shipments s ON s.order_id = o.order_id
LEFT JOIN public.escrow e ON e.order_id = o.order_id
LEFT JOIN public.payments p ON p.order_id = o.order_id
WHERE o.order_number = 'TL-261017-DC4116C2';
