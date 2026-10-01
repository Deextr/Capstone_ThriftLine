-- Order delivery reports: link community reports + evidence to delivery disputes.

CREATE OR REPLACE FUNCTION public.abandon_open_report(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR p_report_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.reporter_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report can no longer be removed.');
  END IF;

  DELETE FROM public.report_evidence e WHERE e.report_id = p_report_id;
  DELETE FROM public.reports r WHERE r.report_id = p_report_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_open_report(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.abandon_open_report(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.attach_report_evidence(
  p_report_id uuid,
  p_file_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
  v_prefix text;
  v_path text;
  v_count integer;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_path := NULLIF(btrim(COALESCE(p_file_path, '')), '');
  IF v_path IS NULL OR v_path LIKE '%..%' OR v_path LIKE '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.reporter_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report can no longer accept photos.');
  END IF;

  v_prefix := v_uid::text || '/' || p_report_id::text || '/';
  IF left(v_path, char_length(v_prefix)) IS DISTINCT FROM v_prefix THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  IF lower(v_path) !~ '\.(jpe?g|png|webp)$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please upload a JPG, PNG, or WebP photo.');
  END IF;

  SELECT count(*) INTO v_count
  FROM public.report_evidence e
  WHERE e.report_id = p_report_id;

  IF v_count >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can attach up to 3 photos.');
  END IF;

  INSERT INTO public.report_evidence (report_id, file_path)
  VALUES (p_report_id, v_path)
  RETURNING report_evidence_id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_evidence_id', v_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo is already attached.');
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

REVOKE ALL ON FUNCTION public.report_delivery_problem(uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_delivery_problem(uuid, text, text, uuid) TO authenticated;
