-- Pay retry: revive failed/expired payment rows on pending orders; trust service JWT for edge prepare.

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

DROP FUNCTION IF EXISTS public.prepare_paymongo_checkout(uuid, text);

CREATE OR REPLACE FUNCTION public.prepare_paymongo_checkout(
  p_order_id uuid,
  p_channel text DEFAULT 'gcash',
  p_buyer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_jwt_role text := COALESCE(auth.jwt() ->> 'role', auth.role());
  v_order public.orders%ROWTYPE;
  v_sib public.orders%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_lead public.payments%ROWTYPE;
  v_centavos integer := 0;
  v_reuse boolean := false;
  v_channel text;
  v_count integer := 0;
BEGIN
  PERFORM public.expire_unpaid_checkouts();
  PERFORM public.expire_auction_payment_offers();

  v_buyer := auth.uid();
  IF p_buyer_id IS NOT NULL THEN
    IF v_jwt_role = 'service_role' THEN
      v_buyer := p_buyer_id;
    ELSIF v_buyer IS NULL OR v_buyer IS DISTINCT FROM p_buyer_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
    END IF;
  END IF;

  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to pay.');
  END IF;

  v_channel := lower(btrim(COALESCE(p_channel, 'gcash')));
  IF v_channel NOT IN ('card', 'gcash') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose Card or GCash.');
  END IF;

  IF p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    IF v_order.passed_bidder_id IS NOT DISTINCT FROM v_buyer
       OR v_order.auction_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Your payment window for this auction has ended.'
      );
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.auction_id IS NOT NULL
     AND v_order.payment_due_at IS NOT NULL
     AND v_order.payment_due_at <= now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your payment window for this auction has ended.'
    );
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',
      CASE
        WHEN v_order.auction_id IS NOT NULL
          THEN 'Your payment window for this auction has ended.'
        ELSE 'This checkout was not completed. The item is back in your cart.'
      END
    );
  END IF;

  IF v_order.order_status = 'disputed'::public.order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order cannot be paid.');
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::public.order_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = v_order.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.buyer_id = v_buyer
      AND o.order_status = 'pending'::public.order_status_enum
      AND (
        o.order_id = v_order.order_id
        OR (
          v_order.checkout_group_id IS NOT NULL
          AND v_order.auction_id IS NULL
          AND o.checkout_group_id = v_order.checkout_group_id
          AND o.auction_id IS NULL
        )
      )
      AND NOT public.order_delivery_address_ready(o.shipping_address)
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Add a delivery address before paying.'
    );
  END IF;

  FOR v_sib IN
    SELECT *
    FROM public.orders o
    WHERE o.buyer_id = v_buyer
      AND o.order_status = 'pending'::public.order_status_enum
      AND (
        o.order_id = v_order.order_id
        OR (
          v_order.checkout_group_id IS NOT NULL
          AND v_order.auction_id IS NULL
          AND o.checkout_group_id = v_order.checkout_group_id
          AND o.auction_id IS NULL
        )
      )
    ORDER BY o.created_at, o.order_id
    FOR UPDATE
  LOOP
    v_payment := public.ensure_pending_order_payment(v_sib, v_channel);
    v_centavos := v_centavos + COALESCE(v_payment.amount_centavos, 0);
    v_count := v_count + 1;
    IF v_sib.order_id = v_order.order_id THEN
      v_lead := v_payment;
    END IF;
  END LOOP;

  IF v_lead.payment_id IS NULL OR v_centavos < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order has no payable amount.');
  END IF;

  IF v_lead.checkout_session_id IS NOT NULL
     AND v_lead.checkout_url IS NOT NULL
     AND v_lead.paymongo_channel IS NOT DISTINCT FROM v_channel
     AND v_lead.updated_at > now() - interval '15 minutes'
     AND (
       v_order.auction_offer_started_at IS NULL
       OR v_lead.created_at >= v_order.auction_offer_started_at
     ) THEN
    v_reuse := true;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'reuse', v_reuse,
    'payment_id', v_lead.payment_id,
    'order_id', v_order.order_id,
    'order_ids', (
      SELECT coalesce(jsonb_agg(o.order_id ORDER BY o.created_at), '[]'::jsonb)
      FROM public.orders o
      WHERE o.buyer_id = v_buyer
        AND o.order_status = 'pending'::public.order_status_enum
        AND (
          o.order_id = v_order.order_id
          OR (
            v_order.checkout_group_id IS NOT NULL
            AND o.checkout_group_id = v_order.checkout_group_id
          )
        )
    ),
    'checkout_group_id', v_order.checkout_group_id,
    'order_count', v_count,
    'order_number', v_order.order_number,
    'total_amount', (v_centavos::numeric / 100),
    'amount_centavos', v_centavos,
    'currency', 'PHP',
    'channel', v_channel,
    'checkout_url', CASE WHEN v_reuse THEN v_lead.checkout_url ELSE NULL END,
    'session_id', CASE WHEN v_reuse THEN v_lead.checkout_session_id ELSE NULL END,
    'previous_session_id', CASE WHEN v_reuse THEN NULL ELSE v_lead.checkout_session_id END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_paymongo_checkout(uuid, text, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_paymongo_checkout(uuid, text, uuid)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.attach_paymongo_checkout(uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.attach_paymongo_checkout(uuid, text, text, uuid)
  TO postgres, service_role;
