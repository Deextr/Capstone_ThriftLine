-- Order-linked buyer reports (inspection / delivery problem): optional details except category other.
-- Aligns submit_order_report with submit_community_report and the Flutter buyer UI.

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_details_len;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_details_len CHECK (
    char_length(details) BETWEEN 0 AND 1000
  );

CREATE OR REPLACE FUNCTION public.submit_order_report(
  p_order_id uuid,
  p_category text,
  p_details text,
  p_delivery_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text;
  v_details text;
  v_order public.orders%ROWTYPE;
  v_report_id uuid;
  v_submission_id uuid;
  v_reported uuid;
  v_paid_at timestamptz;
  v_buyer_categories constant text[] := ARRAY[
    'seller_not_processing_order',
    'counterfeit_received',
    'item_not_as_described',
    'undisclosed_damage',
    'counterfeit_item',
    'fake_product',
    'failure_to_ship',
    'other'
  ];
  v_seller_categories constant text[] := ARRAY[
    'buyer_delivery_pin_issue',
    'other'
  ];
BEGIN
  IF v_uid IS NULL OR p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  v_category := lower(btrim(coalesce(p_category, '')));
  v_details := btrim(coalesce(p_details, ''));

  IF v_order.buyer_id = v_uid THEN
    IF NOT (v_category = ANY (v_buyer_categories)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
    END IF;
    v_reported := v_order.seller_id;
  ELSIF v_order.seller_id = v_uid THEN
    IF NOT (v_category = ANY (v_seller_categories)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
    END IF;
    v_reported := v_order.buyer_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'You are not part of this order.');
  END IF;

  IF v_reported IS NULL OR v_reported = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
  END IF;

  IF v_category = 'other' THEN
    IF char_length(v_details) < 10 OR char_length(v_details) > 1000 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Please describe the issue (10-1,000 characters).'
      );
    END IF;
  ELSIF char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep your report under 1,000 characters.'
    );
  END IF;

  IF v_order.order_status IN (
    'pending'::public.order_status_enum,
    'cancelled'::public.order_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
  END IF;

  IF v_category = 'seller_not_processing_order' AND v_order.buyer_id = v_uid THEN
    IF NOT public.order_is_stuck_preparing(p_order_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'This order is already moving. Use Track delivery if you need an update.'
      );
    END IF;
    v_paid_at := public.order_paid_at(p_order_id);
    IF v_paid_at IS NULL OR v_paid_at > now() - interval '48 hours' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'You can report a shipping delay 48 hours after payment if the seller has not updated this order.'
      );
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reports r
    WHERE r.reporter_id = v_uid
      AND r.order_id = p_order_id
      AND r.status IN (
        'under_review'::public.report_status_enum,
        'needs_more_evidence'::public.report_status_enum
      )
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have an active report for this order.'
    );
  END IF;

  INSERT INTO public.reports (
    reporter_id, reported_user_id, order_id, category, details, status, evidence_attempt_count
  ) VALUES (
    v_uid, v_reported, p_order_id, v_category, v_details,
    'under_review'::public.report_status_enum, 1
  )
  RETURNING report_id INTO v_report_id;

  v_submission_id := public._ensure_report_submission(v_report_id, 1, v_uid);

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Report submitted',
    'Your report has been submitted and is under review.',
    jsonb_build_object('report_id', v_report_id, 'status', 'under_review')
  );

  RETURN jsonb_build_object(
    'success', true,
    'report_id', v_report_id,
    'submission_id', v_submission_id,
    'delivery_reason', p_delivery_reason
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have an active report for this order.'
    );
END;
$$;

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

  IF v_reason = 'other'::public.delivery_dispute_reason_enum THEN
    IF v_details IS NULL OR char_length(v_details) < 10 OR char_length(v_details) > 1000 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Please describe the issue (10-1,000 characters).'
      );
    END IF;
  ELSIF v_details IS NOT NULL AND char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep your description under 1,000 characters.'
    );
  END IF;

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
