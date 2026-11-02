-- Buyer refund snapshot by order (Report Details / Track Order) and clearer GCash notification copy.

CREATE OR REPLACE FUNCTION public.get_my_order_refund_status(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT
    o.order_id,
    o.order_number,
    p.payment_id,
    p.payment_status::text AS payment_status,
    e.escrow_id,
    e.status::text AS escrow_status,
    e.refund_state::text AS refund_state,
    e.refunded_at,
    e.refund_completed_at,
    e.amount_centavos,
    e.refund_provider_status,
    d.transfer_link,
    d.transfer_link_expires_at,
    (d.gcash_submitted_at IS NOT NULL) AS refund_gcash_submitted,
    d.manual_reference AS manual_refund_reference,
    (
      d.manual_evidence_path IS NOT NULL
      AND btrim(d.manual_evidence_path) <> ''
    ) AS refund_proof_available
  INTO v_row
  FROM public.orders o
  JOIN public.escrow e ON e.order_id = o.order_id
  JOIN public.payments p ON p.payment_id = e.payment_id
  LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
  WHERE o.order_id = p_order_id
    AND o.buyer_id = v_uid
    AND e.status = 'refunded'::public.escrow_status_enum
    AND e.refund_state IS NOT NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No refund on this order.');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_row.order_id,
    'order_number', v_row.order_number,
    'payment_id', v_row.payment_id,
    'payment_status', v_row.payment_status,
    'escrow_id', v_row.escrow_id,
    'escrow_status', v_row.escrow_status,
    'refund_state', v_row.refund_state,
    'refunded_at', v_row.refunded_at,
    'refund_completed_at', v_row.refund_completed_at,
    'amount_centavos', v_row.amount_centavos,
    'refund_amount_centavos', CASE
      WHEN v_row.escrow_status = 'refunded' THEN v_row.amount_centavos
      ELSE NULL
    END,
    'refund_provider_status', v_row.refund_provider_status,
    'refund_transfer_link', CASE
      WHEN v_row.refund_state = 'awaiting_buyer_claim' THEN v_row.transfer_link
      ELSE NULL
    END,
    'refund_transfer_link_expires_at', CASE
      WHEN v_row.refund_state = 'awaiting_buyer_claim'
        THEN v_row.transfer_link_expires_at
      ELSE NULL
    END,
    'refund_gcash_submitted', v_row.refund_gcash_submitted,
    'manual_refund_reference', v_row.manual_refund_reference,
    'refund_proof_available', v_row.refund_proof_available
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_order_refund_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_order_refund_status(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_my_order_refund_status(uuid) IS
  'Returns refund progress for the signed-in buyer on one order (escrow + GCash submission flags).';

CREATE OR REPLACE FUNCTION public._notify_refund_buyer(
  p_escrow public.escrow,
  p_state public.escrow_refund_state_enum
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_number text;
  v_amount text := public._peso_text(p_escrow.amount_centavos);
  v_title text;
  v_body text;
BEGIN
  SELECT COALESCE(o.order_number, '') INTO v_number
  FROM public.orders o
  WHERE o.order_id = p_escrow.order_id;

  CASE p_state
    WHEN 'succeeded' THEN
      v_title := 'Refund completed';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' was confirmed.';
    WHEN 'provider_pending' THEN
      v_title := 'Refund pending';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' is being processed. We will update Transaction History when it is done.';
    WHEN 'awaiting_buyer_claim' THEN
      v_title := 'Refund pending';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' is still in progress. Open Transaction History for the latest status.';
    WHEN 'manual_required' THEN
      v_title := 'Refund approved';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' was approved. Add your GCash details in Report details, your order, or Transaction History. ' ||
        'Our team will send the money manually through GCash.';
    WHEN 'manual_completed' THEN
      v_title := 'Refund completed';
      v_body := 'Our team sent your ' || v_amount || ' refund for Order #' ||
        v_number || ' to your GCash.';
    ELSE
      RETURN;
  END CASE;

  PERFORM public.notify_user(
    p_escrow.buyer_id,
    'orderConfirmed',
    v_title,
    v_body,
    jsonb_build_object(
      'order_id', p_escrow.order_id,
      'escrow_id', p_escrow.escrow_id,
      'refund_state', p_state::text
    ),
    'buyer'::public.notification_audience_enum
  );
END;
$$;
