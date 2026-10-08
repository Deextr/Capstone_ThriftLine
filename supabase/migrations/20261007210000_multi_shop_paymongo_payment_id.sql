-- Multi-shop checkout: one PayMongo charge funds multiple seller payment rows.
-- payments_paymongo_payment_uidx blocked mark_order_paid_from_payment on the
-- 2nd+ sibling (same pay_ id), so apply_paymongo_event rolled back and Return
-- to Merchant left every order unpaid. Allow shared provider payment ids across
-- allocations in the same checkout; keep lookups via a non-unique index.
-- checkout_session_id stays unique (session attaches to the lead payment only).

DROP INDEX IF EXISTS public.payments_paymongo_payment_uidx;

CREATE INDEX IF NOT EXISTS payments_paymongo_payment_idx
  ON public.payments (paymongo_payment_id)
  WHERE paymongo_payment_id IS NOT NULL;

COMMENT ON INDEX public.payments_paymongo_payment_idx IS
  'Lookup PayMongo payment id across per-seller allocations (not unique).';

-- Harden paid marking: siblings share pay_/cs_ refs as allocation metadata only.
CREATE OR REPLACE FUNCTION public.mark_order_paid_from_payment(
  p_order public.orders,
  p_payment public.payments,
  p_session_id text,
  p_paymongo_payment_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_notified boolean := false;
  v_pay_id text := NULLIF(btrim(COALESCE(p_paymongo_payment_id, '')), '');
  v_session text := NULLIF(btrim(COALESCE(p_session_id, '')), '');
BEGIN
  UPDATE public.payments
  SET payment_status = 'paid'::public.payment_status_enum,
      paymongo_payment_id = COALESCE(v_pay_id, paymongo_payment_id),
      transaction_reference = COALESCE(v_session, transaction_reference)
  WHERE payment_id = p_payment.payment_id
    AND payment_status IS DISTINCT FROM 'paid'::public.payment_status_enum;

  IF p_order.order_status = 'pending'::public.order_status_enum THEN
    UPDATE public.orders
    SET order_status = 'paid'::public.order_status_enum
    WHERE order_id = p_order.order_id
      AND order_status = 'pending'::public.order_status_enum;

    IF FOUND THEN
      PERFORM public.notify_user(
        p_order.buyer_id,
        'orderConfirmed',
        'Payment successful',
        CASE
          WHEN p_payment.paymongo_channel = 'gcash'
            THEN 'Your GCash payment has been received. Order #'
          ELSE 'Your card payment has been received. Order #'
        END || COALESCE(p_order.order_number, '') || ' is paid.',
        jsonb_build_object('order_id', p_order.order_id)
      );
      PERFORM public.notify_user(
        p_order.seller_id,
        'system',
        'New paid order',
        'A buyer has completed payment for Order #' ||
          COALESCE(p_order.order_number, '') || '.',
        jsonb_build_object('order_id', p_order.order_id)
      );
      v_notified := true;
    END IF;
  END IF;

  RETURN v_notified;
END;
$$;

-- prepare_paymongo_checkout: already-paid when any sibling in the group is paid.
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

  -- Combined checkout: if any sibling is already paid, treat as paid (no second charge).
  IF EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.buyer_id = v_buyer
      AND (
        o.order_id = v_order.order_id
        OR (
          v_order.checkout_group_id IS NOT NULL
          AND v_order.auction_id IS NULL
          AND o.checkout_group_id = v_order.checkout_group_id
          AND o.auction_id IS NULL
        )
      )
      AND (
        o.order_status = 'paid'::public.order_status_enum
        OR EXISTS (
          SELECT 1 FROM public.payments p
          WHERE p.order_id = o.order_id
            AND p.payment_status = 'paid'::public.payment_status_enum
        )
      )
  ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number,
      'checkout_group_id', v_order.checkout_group_id
    );
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
