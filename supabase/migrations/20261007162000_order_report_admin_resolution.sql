-- Order report admin resolution: link disputes, audit fields, idempotent report closure after escrow.

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS resolution_financial text,
  ADD COLUMN IF NOT EXISTS resolution_return_required boolean;

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_resolution_financial_chk;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_resolution_financial_chk CHECK (
    resolution_financial IS NULL
    OR resolution_financial IN ('refund_buyer', 'release_seller')
  );

COMMENT ON COLUMN public.reports.resolution_financial IS
  'Admin escrow outcome for order-linked reports (refund_buyer | release_seller).';
COMMENT ON COLUMN public.reports.resolution_return_required IS
  'When resolution_financial = refund_buyer, whether the buyer must return the item.';

-- Backfill dispute_id on order reports that have an open/resolved delivery dispute.
UPDATE public.reports r
SET dispute_id = d.dispute_id
FROM public.delivery_disputes d
WHERE r.order_id = d.order_id
  AND r.dispute_id IS NULL;

CREATE OR REPLACE FUNCTION public.report_delivery_problem(
  p_order_id uuid,
  p_reason text,
  p_details text DEFAULT NULL,
  p_report_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_reason public.delivery_dispute_reason_enum;
  v_dispute_id uuid;
  v_details text;
  v_report public.reports%ROWTYPE;
  v_evidence_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  BEGIN
    v_reason := btrim(COALESCE(p_reason, ''))::public.delivery_dispute_reason_enum;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('success', false, 'error', 'Choose a valid reason.');
  END;

  v_details := NULLIF(btrim(COALESCE(p_details, '')), '');

  IF p_report_id IS NOT NULL THEN
    SELECT * INTO v_report
    FROM public.reports
    WHERE report_id = p_report_id;

    IF NOT FOUND
       OR v_report.reporter_id IS DISTINCT FROM auth.uid()
       OR v_report.order_id IS DISTINCT FROM p_order_id THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Link this delivery report to your submitted report.'
      );
    END IF;

    SELECT count(*) INTO v_evidence_count
    FROM public.report_evidence e
    WHERE e.report_id = p_report_id;

    IF v_evidence_count < 1 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Please attach at least one photo as evidence.'
      );
    END IF;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_shipment.delivery_verified_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You can report a problem during the inspection period.'
    );
  END IF;

  IF v_order.order_status = 'completed'::public.order_status_enum
     OR v_shipment.delivery_status = 'completed'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order has already been completed.'
    );
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order was cancelled.'
    );
  END IF;

  SELECT d.dispute_id INTO v_dispute_id
  FROM public.delivery_disputes d
  WHERE d.order_id = p_order_id
    AND d.status = 'open'::public.delivery_dispute_status_enum
  LIMIT 1;

  IF v_dispute_id IS NOT NULL THEN
    IF p_report_id IS NOT NULL THEN
      UPDATE public.reports
      SET dispute_id = v_dispute_id
      WHERE report_id = p_report_id
        AND dispute_id IS NULL;
    END IF;
    RETURN jsonb_build_object(
      'success', true,
      'already_reported', true,
      'dispute_id', v_dispute_id,
      'report_id', p_report_id
    );
  END IF;

  INSERT INTO public.delivery_disputes (
    shipment_id, order_id, buyer_id, reason, details
  )
  VALUES (
    v_shipment.shipment_id,
    p_order_id,
    v_order.buyer_id,
    v_reason,
    v_details
  )
  RETURNING dispute_id INTO v_dispute_id;

  IF p_report_id IS NOT NULL THEN
    UPDATE public.reports
    SET dispute_id = v_dispute_id
    WHERE report_id = p_report_id;
  END IF;

  UPDATE public.shipments
  SET delivery_status = 'disputed'::public.delivery_status_enum
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'delivery_dispute_created',
    v_shipment.delivery_status,
    'disputed'::public.delivery_status_enum,
    jsonb_build_object('reason', v_reason::text, 'report_id', p_report_id)
  );
  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    'disputed'::public.delivery_status_enum
  );

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Delivery problem reported',
    'A delivery problem was reported for Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_reported', false,
    'dispute_id', v_dispute_id,
    'report_id', p_report_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_order_report_resolution(
  p_report_id uuid,
  p_financial text,
  p_return_required boolean DEFAULT NULL,
  p_admin_response text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_financial text;
  v_response text;
  v_report public.reports%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_report_status public.report_status_enum;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can close this order report.'
    );
  END IF;

  v_financial := lower(btrim(coalesce(p_financial, '')));
  IF v_financial NOT IN ('refund_buyer', 'release_seller') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a valid financial resolution.');
  END IF;

  v_response := btrim(coalesce(p_admin_response, ''));
  IF char_length(v_response) < 8 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Write a clear resolution note for the reporter.'
    );
  END IF;
  IF char_length(v_response) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the resolution note under 2,000 characters.'
    );
  END IF;

  IF v_financial = 'refund_buyer' AND p_return_required IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Choose whether the item must be returned.'
    );
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order report not found.');
  END IF;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_report.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No payment record was found for this order.'
    );
  END IF;

  IF v_financial = 'refund_buyer'
     AND v_escrow.status IS DISTINCT FROM 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Refund the buyer before closing this report.'
    );
  END IF;

  IF v_financial = 'release_seller'
     AND v_escrow.status IS DISTINCT FROM 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Release payment to the seller before closing this report.'
    );
  END IF;

  v_report_status := CASE v_financial
    WHEN 'refund_buyer' THEN 'resolved'::public.report_status_enum
    ELSE 'dismissed'::public.report_status_enum
  END;

  IF v_report.status IN (
    'resolved'::public.report_status_enum,
    'dismissed'::public.report_status_enum
  ) THEN
    IF v_report.resolution_financial = v_financial
       AND v_report.status = v_report_status THEN
      RETURN jsonb_build_object(
        'success', true,
        'already_decided', true,
        'report_id', v_report.report_id,
        'status', v_report.status::text,
        'resolution_financial', v_report.resolution_financial
      );
    END IF;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order report has already been closed with a different outcome.'
    );
  END IF;

  IF v_report.status NOT IN (
    'under_review'::public.report_status_enum,
    'needs_more_evidence'::public.report_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report cannot be closed.');
  END IF;

  UPDATE public.reports
  SET
    status = v_report_status,
    admin_response = v_response,
    reporter_instruction = NULL,
    reviewed_by = v_uid,
    resolved_at = now(),
    resolution_financial = v_financial,
    resolution_return_required = CASE
      WHEN v_financial = 'refund_buyer' THEN p_return_required
      ELSE NULL
    END
  WHERE report_id = p_report_id;

  PERFORM public.notify_user(
    v_report.reporter_id,
    'report_decision',
    CASE v_financial
      WHEN 'refund_buyer' THEN 'Order dispute resolved in your favor'
      ELSE 'Order dispute dismissed'
    END,
    CASE
      WHEN v_financial = 'refund_buyer' AND p_return_required IS TRUE THEN
        'The admin resolved this order dispute in your favor. Prepare the item for pickup—the seller will arrange the return.'
      WHEN v_financial = 'refund_buyer' THEN
        'The admin resolved this order dispute in your favor. No item return is required.'
      ELSE
        'Your order dispute was reviewed and dismissed.'
    END,
    jsonb_build_object(
      'report_id', p_report_id,
      'status', v_report_status::text,
      'resolution_financial', v_financial
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'report_id', p_report_id,
    'status', v_report_status::text,
    'resolution_financial', v_financial,
    'resolution_return_required', p_return_required
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_order_report_resolution(uuid, text, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_order_report_resolution(uuid, text, boolean, text)
  TO authenticated;
