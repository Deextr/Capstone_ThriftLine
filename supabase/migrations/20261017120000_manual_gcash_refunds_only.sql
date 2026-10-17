-- Buyer refunds: manual GCash only (no new PayMongo refund API / claim links).
-- PayMongo checkout and payment webhooks unchanged.

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
      v_title := 'Refund pending';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' was approved. Add your GCash details in Transaction History. Our team will send the money manually through GCash.';
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

CREATE OR REPLACE FUNCTION public._record_escrow_refund_decision(
  p_escrow_id uuid,
  p_provider text,
  p_paymongo_refund_id text,
  p_provider_status text,
  p_transfer_link text,
  p_transfer_link_expires_at timestamptz,
  p_provider_error text,
  p_default_reason text
)
RETURNS public.escrow_refund_state_enum
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_state public.escrow_refund_state_enum;
  v_escrow public.escrow%ROWTYPE;
  v_link text := NULLIF(btrim(coalesce(p_transfer_link, '')), '');
BEGIN
  v_state := public._resolve_refund_state(v_provider, p_provider_status, v_link);

  UPDATE public.escrow
  SET
    status = 'refunded'::public.escrow_status_enum,
    refunded_at = now(),
    refund_reason = COALESCE(refund_reason, p_default_reason),
    refund_lock_at = NULL,
    refund_provider = v_provider::public.escrow_refund_provider_enum,
    paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    refund_provider_status = COALESCE(
      NULLIF(btrim(coalesce(p_provider_status, '')), ''),
      v_provider
    ),
    refund_state = v_state,
    refund_provider_error = NULLIF(btrim(coalesce(p_provider_error, '')), ''),
    refund_last_checked_at = now(),
    refund_completed_at = CASE
      WHEN v_state = 'succeeded'::public.escrow_refund_state_enum THEN now()
      ELSE NULL
    END
  WHERE escrow_id = p_escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
  RETURNING * INTO v_escrow;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, transfer_link, transfer_link_expires_at
  )
  VALUES (
    v_escrow.escrow_id,
    v_escrow.buyer_id,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN v_link ELSE NULL END,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN p_transfer_link_expires_at ELSE NULL END
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET transfer_link = EXCLUDED.transfer_link,
      transfer_link_expires_at = EXCLUDED.transfer_link_expires_at;

  IF v_state = 'succeeded'::public.escrow_refund_state_enum THEN
    UPDATE public.payments
    SET payment_status = 'refunded'::public.payment_status_enum
    WHERE payment_id = v_escrow.payment_id
      AND payment_status = 'paid'::public.payment_status_enum;
  END IF;

  IF v_state = 'manual_required'::public.escrow_refund_state_enum THEN
    PERFORM public._notify_refund_admins(
      v_escrow,
      'Manual GCash refund needed',
      'Send ' || public._peso_text(v_escrow.amount_centavos) ||
        ' to the buyer through GCash for Order #' ||
        COALESCE(
          (SELECT o.order_number FROM public.orders o WHERE o.order_id = v_escrow.order_id),
          ''
        ) || ', then record the transfer in Buyer refunds.'
    );
  END IF;

  RETURN v_state;
END;
$$;

-- Block new PayMongo refund retries; manual GCash is the supported path.
CREATE OR REPLACE FUNCTION public.prepare_refund_retry(p_escrow_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can retry this refund.');
  END IF;

  RETURN jsonb_build_object(
    'success', false,
    'error',
    'Buyer refunds are sent manually through GCash. Send the money, then use Record manual GCash refund.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_refund_retry(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_refund_retry(uuid) TO authenticated;
