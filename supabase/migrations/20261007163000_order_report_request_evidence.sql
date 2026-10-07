-- Order report: admin requests more evidence without touching escrow.

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS evidence_requested_user_id uuid REFERENCES public.users (user_id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.admin_request_order_report_evidence(
  p_report_id uuid,
  p_party text,
  p_instruction text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_party text;
  v_instruction text;
  v_report public.reports%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_target uuid;
  v_attempt smallint;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can request evidence.'
    );
  END IF;

  v_party := lower(btrim(coalesce(p_party, '')));
  IF v_party NOT IN ('buyer', 'seller', 'reporter') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose who should provide evidence.');
  END IF;

  v_instruction := btrim(coalesce(p_instruction, ''));
  IF char_length(v_instruction) < 20 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Describe what evidence is needed (at least 20 characters).'
    );
  END IF;
  IF char_length(v_instruction) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the request under 2,000 characters.'
    );
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order report not found.');
  END IF;

  IF v_report.status IN (
    'resolved'::public.report_status_enum,
    'dismissed'::public.report_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This report is already closed.'
    );
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_report.order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  v_target := CASE v_party
    WHEN 'buyer' THEN v_order.buyer_id
    WHEN 'seller' THEN v_order.seller_id
    ELSE v_report.reporter_id
  END;

  IF v_target IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not determine who to notify.');
  END IF;

  v_attempt := v_report.evidence_attempt_count;
  IF v_report.status = 'needs_more_evidence'::public.report_status_enum THEN
    IF v_attempt >= 3 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Maximum evidence attempts reached. Refund or release payment instead.'
      );
    END IF;
  END IF;

  UPDATE public.reports
  SET
    status = 'needs_more_evidence'::public.report_status_enum,
    reporter_instruction = v_instruction,
    evidence_requested_user_id = v_target,
    reviewed_by = v_uid
  WHERE report_id = p_report_id;

  PERFORM public.notify_user(
    v_target,
    'system',
    'More evidence needed for your order report',
    v_instruction,
    jsonb_build_object(
      'report_id', p_report_id,
      'order_id', v_order.order_id,
      'status', 'needs_more_evidence'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'report_id', p_report_id,
    'status', 'needs_more_evidence',
    'evidence_requested_user_id', v_target,
    'attempt_number', v_attempt
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_request_order_report_evidence(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_request_order_report_evidence(uuid, text, text)
  TO authenticated;
