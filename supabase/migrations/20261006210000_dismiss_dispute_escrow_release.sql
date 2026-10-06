-- When an admin closes/dismisses a delivery dispute (buyer claim rejected), clear the
-- escrow dispute hold and resume the order lifecycle so seller_earnings_snapshot
-- reflects authoritative escrow state (held → released when eligible).

CREATE OR REPLACE FUNCTION public.resume_order_after_dispute_closed(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_shipment public.shipments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_open boolean;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = p_order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) INTO v_open;

  IF v_open THEN
    RETURN;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_order.order_status IN (
       'completed'::public.order_status_enum,
       'cancelled'::public.order_status_enum
     ) THEN
    RETURN;
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_shipment.delivery_status IS DISTINCT FROM 'disputed'::public.delivery_status_enum
     OR v_shipment.delivery_verified_at IS NULL THEN
    RETURN;
  END IF;

  IF v_shipment.inspection_expires_at IS NOT NULL
     AND v_shipment.inspection_expires_at <= now() THEN
    UPDATE public.shipments
    SET
      delivery_status = 'completed'::public.delivery_status_enum,
      auto_completed = true,
      completion_reason = COALESCE(
        completion_reason,
        'inspection_expired_dispute_dismissed'
      ),
      completed_at = COALESCE(completed_at, now())
    WHERE shipment_id = v_shipment.shipment_id
      AND delivery_status = 'disputed'::public.delivery_status_enum;

    IF FOUND THEN
      PERFORM public.record_delivery_event(
        v_shipment.shipment_id,
        p_order_id,
        NULL,
        'order_auto_completed',
        'disputed'::public.delivery_status_enum,
        'completed'::public.delivery_status_enum,
        jsonb_build_object('reason', 'inspection_expired_dispute_dismissed')
      );
      PERFORM public.sync_order_status_for_delivery(
        p_order_id,
        'completed'::public.delivery_status_enum
      );
    END IF;
    RETURN;
  END IF;

  UPDATE public.shipments
  SET delivery_status = 'inspection_period'::public.delivery_status_enum
  WHERE shipment_id = v_shipment.shipment_id
    AND delivery_status = 'disputed'::public.delivery_status_enum;

  IF FOUND THEN
    PERFORM public.sync_order_status_for_delivery(
      p_order_id,
      'inspection_period'::public.delivery_status_enum
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_escrow_after_dispute_closed(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_open boolean;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = p_order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) INTO v_open;

  IF v_open THEN
    RETURN false;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  PERFORM public.ensure_order_escrow_hold(p_order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN true;
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum
     OR v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN false;
  END IF;

  IF v_order.order_status = 'completed'::public.order_status_enum THEN
    RETURN public.try_auto_release_escrow(p_order_id);
  END IF;

  UPDATE public.escrow
  SET status = 'held'::public.escrow_status_enum
  WHERE escrow_id = v_escrow.escrow_id
    AND status = 'disputed'::public.escrow_status_enum;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_delivery_dispute(
  p_dispute_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_note text;
  v_dispute public.delivery_disputes%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can close a delivery problem.'
    );
  END IF;

  IF p_dispute_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the note under 2,000 characters.'
    );
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  IF v_dispute.status IS DISTINCT FROM 'open'::public.delivery_dispute_status_enum THEN
    PERFORM public.resume_order_after_dispute_closed(v_dispute.order_id);
    PERFORM public.resume_escrow_after_dispute_closed(v_dispute.order_id);
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'dispute_id', v_dispute.dispute_id,
      'status', v_dispute.status::text
    );
  END IF;

  UPDATE public.delivery_disputes
  SET
    status = 'resolved'::public.delivery_dispute_status_enum,
    admin_note = v_note,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE dispute_id = p_dispute_id
    AND status = 'open'::public.delivery_dispute_status_enum;

  IF NOT FOUND THEN
    PERFORM public.resume_order_after_dispute_closed(v_dispute.order_id);
    PERFORM public.resume_escrow_after_dispute_closed(v_dispute.order_id);
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'dispute_id', p_dispute_id,
      'status', 'resolved'
    );
  END IF;

  PERFORM public.resume_order_after_dispute_closed(v_dispute.order_id);
  PERFORM public.resume_escrow_after_dispute_closed(v_dispute.order_id);

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'dispute_id', p_dispute_id,
    'status', 'resolved'
  );
END;
$$;

COMMENT ON FUNCTION public.close_delivery_dispute(uuid, text) IS
  'Admin-only. Dismisses an open delivery problem (resolved). Clears escrow dispute hold and resumes order/escrow so seller earnings follow escrow when eligible. Does not refund the buyer.';

COMMENT ON FUNCTION public.resume_order_after_dispute_closed(uuid) IS
  'Internal. Restores inspection/completion after all delivery disputes for an order are closed.';

COMMENT ON FUNCTION public.resume_escrow_after_dispute_closed(uuid) IS
  'Internal. Clears disputed escrow when no open disputes remain; auto-releases when the order is completed.';

REVOKE ALL ON FUNCTION public.resume_order_after_dispute_closed(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resume_escrow_after_dispute_closed(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resume_order_after_dispute_closed(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.resume_escrow_after_dispute_closed(uuid) TO postgres, service_role;

-- Repair rows stuck from the old close_delivery_dispute (dispute resolved, escrow still disputed).
UPDATE public.escrow e
SET status = 'held'::public.escrow_status_enum
WHERE e.status = 'disputed'::public.escrow_status_enum
  AND e.refund_lock_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = e.order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.order_id = e.order_id
      AND o.order_status = 'completed'::public.order_status_enum
  );

UPDATE public.escrow e
SET
  status = 'released'::public.escrow_status_enum,
  released_at = COALESCE(e.released_at, now()),
  release_reason = COALESCE(e.release_reason, 'order_completed')
FROM public.orders o
WHERE o.order_id = e.order_id
  AND o.order_status = 'completed'::public.order_status_enum
  AND e.status IN (
    'held'::public.escrow_status_enum,
    'disputed'::public.escrow_status_enum
  )
  AND e.refund_lock_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = e.order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  );

-- Orders left in disputed delivery while the dispute is already closed.
DO $$
DECLARE
  v_row record;
BEGIN
  FOR v_row IN
    SELECT s.order_id
    FROM public.shipments s
    WHERE s.delivery_status = 'disputed'::public.delivery_status_enum
      AND s.delivery_verified_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.delivery_disputes d
        WHERE d.order_id = s.order_id
          AND d.status = 'open'::public.delivery_dispute_status_enum
      )
  LOOP
    PERFORM public.resume_order_after_dispute_closed(v_row.order_id);
    PERFORM public.resume_escrow_after_dispute_closed(v_row.order_id);
  END LOOP;
END;
$$;
