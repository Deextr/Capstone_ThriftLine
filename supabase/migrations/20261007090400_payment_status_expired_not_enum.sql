-- payment_status_enum is pending | paid | failed | refunded (Phase 5/6).
-- PayMongo session expiration is stored as failed + voided order; "expired" is
-- a client/reconcile outcome string only, not a PostgreSQL enum label.
-- Recent checkout RPCs incorrectly cast 'expired'::payment_status_enum.

CREATE OR REPLACE FUNCTION public.ensure_pending_order_payment(
  p_order public.orders,
  p_channel text
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_centavos integer;
BEGIN
  v_centavos := round(p_order.total_amount * 100)::integer;
  IF v_centavos IS NULL OR v_centavos < 1 THEN
    RAISE EXCEPTION 'This order has no payable amount.';
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order.order_id
    AND payment_status = 'pending'::public.payment_status_enum
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.payments
    SET total_amount = p_order.total_amount,
        amount_centavos = v_centavos,
        currency = 'PHP',
        payment_method = 'paymongo'::public.payment_method_enum,
        paymongo_channel = p_channel
    WHERE payment_id = v_payment.payment_id
    RETURNING * INTO v_payment;
    RETURN v_payment;
  END IF;

  UPDATE public.payments p
  SET payment_status = 'pending'::public.payment_status_enum,
      checkout_session_id = NULL,
      checkout_url = NULL,
      transaction_reference = NULL,
      paymongo_payment_id = NULL,
      total_amount = p_order.total_amount,
      amount_centavos = v_centavos,
      currency = 'PHP',
      payment_method = 'paymongo'::public.payment_method_enum,
      paymongo_channel = p_channel,
      updated_at = now()
  WHERE p.order_id = p_order.order_id
    AND p.payment_status = 'failed'::public.payment_status_enum
    AND NOT EXISTS (
      SELECT 1
      FROM public.payments p2
      WHERE p2.order_id = p_order.order_id
        AND p2.payment_status = 'paid'::public.payment_status_enum
    )
  RETURNING * INTO v_payment;

  IF FOUND THEN
    RETURN v_payment;
  END IF;

  INSERT INTO public.payments (
    order_id, payment_method, total_amount, payment_status,
    amount_centavos, currency, paymongo_channel
  )
  VALUES (
    p_order.order_id,
    'paymongo'::public.payment_method_enum,
    p_order.total_amount,
    'pending'::public.payment_status_enum,
    v_centavos,
    'PHP',
    p_channel
  )
  RETURNING * INTO v_payment;

  RETURN v_payment;
END;
$$;

CREATE OR REPLACE FUNCTION public.attach_paymongo_checkout(
  p_payment_id uuid,
  p_session_id text,
  p_checkout_url text,
  p_buyer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
BEGIN
  IF p_buyer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to pay.');
  END IF;

  IF p_payment_id IS NULL
     OR p_session_id IS NULL OR btrim(p_session_id) = ''
     OR p_checkout_url IS NULL OR btrim(p_checkout_url) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unable to start payment right now. Please try again.');
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE payment_id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM p_buyer_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF btrim(p_session_id) NOT LIKE 'cs_%'
     OR btrim(p_checkout_url) NOT LIKE 'https://checkout.paymongo.com/%' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Unable to start payment right now. Please try again.'
    );
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum
     OR v_payment.payment_status = 'paid'::payment_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_payment.payment_status IS DISTINCT FROM 'pending'::payment_status_enum THEN
    IF v_order.order_status = 'pending'::order_status_enum
       AND v_payment.payment_status = 'failed'::public.payment_status_enum THEN
      UPDATE public.payments
      SET payment_status = 'pending'::public.payment_status_enum,
          checkout_session_id = NULL,
          checkout_url = NULL,
          transaction_reference = NULL,
          paymongo_payment_id = NULL,
          updated_at = now()
      WHERE payment_id = v_payment.payment_id
      RETURNING * INTO v_payment;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'Unable to start payment right now. Please try again.');
    END IF;
  END IF;

  UPDATE public.payments
  SET checkout_session_id = btrim(p_session_id),
      checkout_url = btrim(p_checkout_url),
      transaction_reference = btrim(p_session_id),
      payment_method = 'paymongo'::payment_method_enum
  WHERE payment_id = v_payment.payment_id;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id,
    'session_id', btrim(p_session_id),
    'checkout_url', btrim(p_checkout_url)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_my_paymongo_checkout(
  p_order_id uuid,
  p_client_outcome text DEFAULT 'failed',
  p_restore_cart boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_order public.orders%ROWTYPE;
  v_outcome text := lower(btrim(COALESCE(p_client_outcome, '')));
  v_result jsonb;
  v_restore boolean := COALESCE(p_restore_cart, true);
  r record;
  v_terminal text;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.checkout_source = 'buy_now' THEN
    v_restore := false;
  END IF;

  IF v_order.order_status = 'paid'::public.order_status_enum
     OR EXISTS (
       SELECT 1 FROM public.payments p
       WHERE p.order_id = v_order.order_id
         AND p.payment_status = 'paid'::public.payment_status_enum
     ) THEN
    RETURN jsonb_build_object('success', true, 'outcome', 'paid');
  END IF;

  IF v_order.auction_id IS NOT NULL
     OR v_order.order_type = 'auction'::public.order_type_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'outcome', CASE WHEN v_outcome = 'expired' THEN 'expired' ELSE 'failed' END,
      'auction', true
    );
  END IF;

  IF v_outcome NOT IN ('failed', 'expired', 'cancel', 'cancelled') THEN
    RETURN jsonb_build_object('success', true, 'outcome', 'pending');
  END IF;

  IF v_order.checkout_group_id IS NOT NULL THEN
    FOR r IN
      SELECT o.order_id
      FROM public.orders o
      WHERE o.checkout_group_id = v_order.checkout_group_id
        AND o.buyer_id = v_buyer
        AND o.order_status = 'pending'::public.order_status_enum
        AND o.auction_id IS NULL
    LOOP
      v_result := public.void_unpaid_checkout(r.order_id, v_restore, true);
    END LOOP;
  ELSE
    v_result := public.void_unpaid_checkout(p_order_id, v_restore, true);
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id;

  IF EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = p_order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
  ) THEN
    v_terminal := 'paid';
  ELSIF v_order.order_status = 'cancelled'::public.order_status_enum
     OR EXISTS (
       SELECT 1 FROM public.payments p
       WHERE p.order_id = p_order_id
         AND p.payment_status = 'failed'::public.payment_status_enum
     )
     OR COALESCE(v_result->>'success', 'false') = 'true' THEN
    v_terminal := CASE WHEN v_outcome = 'expired' THEN 'expired' ELSE 'failed' END;
  ELSE
    v_terminal := 'pending';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'outcome', v_terminal,
    'void', v_result
  );
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text, boolean)
  TO authenticated, postgres, service_role;
