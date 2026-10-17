-- Late PayMongo capture after checkout void, expiry, or auction payment window:
-- record the payment, keep the order non-fulfillable, open manual GCash refund.

-- ===========================================================================
-- 1. Helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION public._paymongo_order_ineligible_for_fulfillment(
  p_order public.orders,
  p_payment public.payments
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_order.order_id IS NULL OR p_payment.payment_id IS NULL THEN
    RETURN false;
  END IF;

  IF p_order.order_status IN (
       'cancelled'::public.order_status_enum,
       'disputed'::public.order_status_enum
     ) THEN
    RETURN true;
  END IF;

  IF p_order.auction_id IS NOT NULL THEN
    RETURN
      p_order.order_status = 'cancelled'::public.order_status_enum
      OR (
        p_order.payment_due_at IS NOT NULL
        AND p_order.payment_due_at <= now()
      )
      OR (
        p_order.auction_offer_started_at IS NOT NULL
        AND p_payment.created_at < p_order.auction_offer_started_at
      )
      OR p_payment.payment_status = 'failed'::public.payment_status_enum;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public._late_paymongo_charge_centavos(
  p_order public.orders,
  p_payment public.payments
)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(sum(p.amount_centavos), 0)::integer
  FROM public.orders o
  JOIN public.payments p ON p.order_id = o.order_id
  WHERE p.amount_centavos IS NOT NULL
    AND p.amount_centavos > 0
    AND p.payment_status IN (
      'pending'::public.payment_status_enum,
      'failed'::public.payment_status_enum,
      'paid'::public.payment_status_enum
    )
    AND (
      o.order_id = p_order.order_id
      OR (
        p_order.checkout_group_id IS NOT NULL
        AND o.checkout_group_id = p_order.checkout_group_id
        AND p_order.auction_id IS NULL
        AND o.auction_id IS NULL
      )
    );
$$;

CREATE OR REPLACE FUNCTION public._capture_paymongo_payment_only(
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
  v_pay_id text := NULLIF(btrim(COALESCE(p_paymongo_payment_id, '')), '');
  v_session text := NULLIF(btrim(COALESCE(p_session_id, '')), '');
BEGIN
  UPDATE public.payments
  SET payment_status = 'paid'::public.payment_status_enum,
      paymongo_payment_id = COALESCE(v_pay_id, paymongo_payment_id),
      transaction_reference = COALESCE(v_session, transaction_reference)
  WHERE payment_id = p_payment.payment_id
    AND payment_status IS DISTINCT FROM 'paid'::public.payment_status_enum;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public._late_paymongo_refund_reason(
  p_order public.orders
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_order.auction_id IS NOT NULL
      THEN 'late_payment_after_auction_deadline'
    ELSE 'late_payment_after_cancellation'
  END;
$$;

-- Record provider-confirmed payment when the order must not be fulfilled.
CREATE OR REPLACE FUNCTION public._reconcile_late_paymongo_success(
  p_order public.orders,
  p_payment public.payments,
  p_session_id text,
  p_paymongo_payment_id text,
  p_amount_centavos integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sib public.orders%ROWTYPE;
  v_sib_pay public.payments%ROWTYPE;
  v_escrow_id uuid;
  v_escrow public.escrow%ROWTYPE;
  v_state public.escrow_refund_state_enum;
  v_expected integer;
  v_reason text;
  v_handled integer := 0;
  v_captured boolean := false;
BEGIN
  IF NOT public._paymongo_order_ineligible_for_fulfillment(p_order, p_payment) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order is still eligible for payment.'
    );
  END IF;

  v_expected := public._late_paymongo_charge_centavos(p_order, p_payment);
  IF v_expected < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payment not found.');
  END IF;

  IF p_amount_centavos IS NULL
     OR p_amount_centavos IS DISTINCT FROM v_expected THEN
    RETURN jsonb_build_object('success', false, 'error', 'Amount mismatch.');
  END IF;

  v_reason := public._late_paymongo_refund_reason(p_order);

  FOR v_sib IN
    SELECT o.*
    FROM public.orders o
    WHERE o.order_id = p_order.order_id
       OR (
         p_order.checkout_group_id IS NOT NULL
         AND p_order.auction_id IS NULL
         AND o.checkout_group_id = p_order.checkout_group_id
         AND o.auction_id IS NULL
       )
    ORDER BY o.created_at, o.order_id
    FOR UPDATE
  LOOP
    SELECT * INTO v_sib_pay
    FROM public.payments p
    WHERE p.order_id = v_sib.order_id
      AND p.payment_status IN (
        'pending'::public.payment_status_enum,
        'failed'::public.payment_status_enum,
        'paid'::public.payment_status_enum
      )
    ORDER BY
      CASE p.payment_status
        WHEN 'pending'::public.payment_status_enum THEN 0
        WHEN 'failed'::public.payment_status_enum THEN 1
        ELSE 2
      END,
      p.created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF v_sib_pay.payment_id IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_escrow
    FROM public.escrow e
    WHERE e.order_id = v_sib.order_id;

    IF v_sib_pay.payment_status = 'paid'::public.payment_status_enum
       AND v_escrow.escrow_id IS NOT NULL
       AND v_escrow.status = 'refunded'::public.escrow_status_enum
       AND v_escrow.refund_state IS NOT NULL THEN
      v_handled := v_handled + 1;
      CONTINUE;
    END IF;

    IF v_sib_pay.payment_status IS DISTINCT FROM 'paid'::public.payment_status_enum THEN
      v_captured := public._capture_paymongo_payment_only(
        v_sib_pay, p_session_id, p_paymongo_payment_id
      );
    END IF;

    v_escrow_id := public.ensure_order_escrow_hold(v_sib.order_id);
    IF v_escrow_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Could not record escrow for late payment.'
      );
    END IF;

    v_state := public._record_escrow_refund_decision(
      v_escrow_id,
      'internal',
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      v_reason
    );

    IF v_state IS NULL THEN
      SELECT * INTO v_escrow
      FROM public.escrow
      WHERE escrow_id = v_escrow_id;

      IF v_escrow.status = 'refunded'::public.escrow_status_enum
         AND v_escrow.refund_state IS NOT NULL THEN
        v_handled := v_handled + 1;
        CONTINUE;
      END IF;

      RETURN jsonb_build_object(
        'success', false,
        'error', 'Could not open refund for late payment.'
      );
    END IF;

    SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow_id;
    PERFORM public._notify_refund_buyer(v_escrow, v_state);
    v_handled := v_handled + 1;
  END LOOP;

  IF v_handled < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payment allocation missing.');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'late_payment_reconciled', true,
    'refund_required', true,
    'refund_reason', v_reason,
    'payment_captured', v_captured,
    'orders_handled', v_handled
  );
END;
$$;

REVOKE ALL ON FUNCTION public._paymongo_order_ineligible_for_fulfillment(
  public.orders, public.payments
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._late_paymongo_charge_centavos(
  public.orders, public.payments
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._capture_paymongo_payment_only(
  public.payments, text, text
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._late_paymongo_refund_reason(public.orders)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._reconcile_late_paymongo_success(
  public.orders, public.payments, text, text, integer
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public._paymongo_order_ineligible_for_fulfillment(
  public.orders, public.payments
) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public._late_paymongo_charge_centavos(
  public.orders, public.payments
) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public._capture_paymongo_payment_only(
  public.payments, text, text
) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public._late_paymongo_refund_reason(public.orders)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public._reconcile_late_paymongo_success(
  public.orders, public.payments, text, text, integer
) TO postgres, service_role;

-- ===========================================================================
-- 2. apply_paymongo_event — late paid capture + refund-required
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.apply_paymongo_event(
  p_event_key text,
  p_event_type text,
  p_session_id text,
  p_paymongo_payment_id text,
  p_amount_centavos integer,
  p_currency text,
  p_metadata_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing public.paymongo_webhook_events%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_sib public.orders%ROWTYPE;
  v_sib_pay public.payments%ROWTYPE;
  v_paid boolean := false;
  v_failed boolean := false;
  v_notified boolean := false;
  v_currency text;
  v_void jsonb;
  v_ineligible boolean := false;
  v_expected integer := 0;
  v_late jsonb;
  v_escrow public.escrow%ROWTYPE;
BEGIN
  IF p_event_key IS NULL OR btrim(p_event_key) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing event key.');
  END IF;

  SELECT * INTO v_existing
  FROM public.paymongo_webhook_events
  WHERE event_key = p_event_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'payment_id', v_existing.payment_id,
      'order_id', v_existing.order_id
    );
  END IF;

  v_paid := p_event_type IN ('checkout_session.payment.paid', 'payment.paid');
  v_failed := p_event_type IN (
    'payment.failed',
    'checkout_session.payment.failed',
    'checkout_session.expired',
    'checkout_session.payment.expired',
    'payment.expired'
  );

  IF NOT v_paid AND NOT v_failed THEN
    INSERT INTO public.paymongo_webhook_events (event_key, event_type)
    VALUES (p_event_key, COALESCE(p_event_type, 'ignored'));
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;

  IF p_session_id IS NOT NULL AND btrim(p_session_id) <> '' THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE checkout_session_id = btrim(p_session_id)
       OR transaction_reference = btrim(p_session_id)
    ORDER BY updated_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL
     AND p_paymongo_payment_id IS NOT NULL
     AND btrim(p_paymongo_payment_id) <> '' THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE paymongo_payment_id = btrim(p_paymongo_payment_id)
    ORDER BY updated_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL AND p_metadata_order_id IS NOT NULL THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE order_id = p_metadata_order_id
      AND payment_status IN (
        'pending'::public.payment_status_enum,
        'failed'::public.payment_status_enum,
        'paid'::public.payment_status_enum
      )
    ORDER BY
      CASE payment_status
        WHEN 'pending'::public.payment_status_enum THEN 0
        WHEN 'failed'::public.payment_status_enum THEN 1
        ELSE 2
      END,
      created_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL THEN
    IF v_failed THEN
      INSERT INTO public.paymongo_webhook_events (event_key, event_type)
      VALUES (p_event_key, COALESCE(p_event_type, 'payment.failed'))
      ON CONFLICT (event_key) DO NOTHING;
      RETURN jsonb_build_object('success', true, 'ignored', true);
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Payment not found.');
  END IF;

  PERFORM public.expire_auction_payment_offers();

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF p_metadata_order_id IS NOT NULL
     AND p_metadata_order_id IS DISTINCT FROM v_order.order_id
     AND (
       v_order.checkout_group_id IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.orders o
         WHERE o.order_id = p_metadata_order_id
           AND o.checkout_group_id = v_order.checkout_group_id
       )
     ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order mismatch.');
  END IF;

  v_currency := upper(COALESCE(NULLIF(btrim(p_currency), ''), 'PHP'));
  IF v_currency IS DISTINCT FROM 'PHP' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Currency mismatch.');
  END IF;

  v_ineligible := public._paymongo_order_ineligible_for_fulfillment(
    v_order, v_payment
  );

  IF v_paid AND v_ineligible THEN
    v_late := public._reconcile_late_paymongo_success(
      v_order,
      v_payment,
      p_session_id,
      p_paymongo_payment_id,
      p_amount_centavos
    );

    IF COALESCE(v_late ->> 'success', 'false') <> 'true' THEN
      RETURN v_late;
    END IF;

    INSERT INTO public.paymongo_webhook_events (
      event_key, event_type, payment_id, order_id
    )
    VALUES (
      p_event_key,
      COALESCE(p_event_type, 'unknown'),
      v_payment.payment_id,
      v_order.order_id
    )
    ON CONFLICT (event_key) DO NOTHING;

    RETURN v_late || jsonb_build_object(
      'duplicate', false,
      'paid', true,
      'payment_id', v_payment.payment_id,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_paid
     AND v_payment.payment_status = 'paid'::public.payment_status_enum THEN
    SELECT * INTO v_escrow
    FROM public.escrow e
    WHERE e.order_id = v_order.order_id;

    IF FOUND
       AND v_escrow.status = 'refunded'::public.escrow_status_enum
       AND v_escrow.refund_reason IN (
         'late_payment_after_cancellation',
         'late_payment_after_auction_deadline'
       ) THEN
      INSERT INTO public.paymongo_webhook_events (
        event_key, event_type, payment_id, order_id
      )
      VALUES (
        p_event_key, COALESCE(p_event_type, 'unknown'),
        v_payment.payment_id, v_order.order_id
      )
      ON CONFLICT (event_key) DO NOTHING;
      RETURN jsonb_build_object(
        'success', true,
        'duplicate', true,
        'late_payment_reconciled', true,
        'payment_id', v_payment.payment_id,
        'order_id', v_order.order_id
      );
    END IF;
  END IF;

  IF v_paid THEN
    IF v_order.order_status IN (
         'cancelled'::public.order_status_enum,
         'disputed'::public.order_status_enum
       ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Late payment could not be reconciled.'
      );
    END IF;

    SELECT COALESCE(sum(p.amount_centavos), 0)
    INTO v_expected
    FROM public.payments p
    JOIN public.orders o ON o.order_id = p.order_id
    WHERE p.payment_status = 'pending'::public.payment_status_enum
      AND o.order_status = 'pending'::public.order_status_enum
      AND (
        o.order_id = v_order.order_id
        OR (
          v_order.checkout_group_id IS NOT NULL
          AND o.checkout_group_id = v_order.checkout_group_id
        )
      );

    IF p_amount_centavos IS NULL
       OR p_amount_centavos IS DISTINCT FROM v_expected THEN
      RETURN jsonb_build_object('success', false, 'error', 'Amount mismatch.');
    END IF;

    FOR v_sib IN
      SELECT *
      FROM public.orders o
      WHERE o.order_status = 'pending'::public.order_status_enum
        AND (
          o.order_id = v_order.order_id
          OR (
            v_order.checkout_group_id IS NOT NULL
            AND o.checkout_group_id = v_order.checkout_group_id
          )
        )
      ORDER BY o.created_at, o.order_id
      FOR UPDATE
    LOOP
      SELECT * INTO v_sib_pay
      FROM public.payments p
      WHERE p.order_id = v_sib.order_id
        AND p.payment_status = 'pending'::public.payment_status_enum
      FOR UPDATE;

      IF v_sib_pay.payment_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payment allocation missing.');
      END IF;

      IF public.mark_order_paid_from_payment(
        v_sib, v_sib_pay, p_session_id, p_paymongo_payment_id
      ) THEN
        v_notified := true;
      END IF;
    END LOOP;
  ELSIF v_failed THEN
    IF v_payment.payment_status = 'paid'::public.payment_status_enum THEN
      INSERT INTO public.paymongo_webhook_events (
        event_key, event_type, payment_id, order_id
      )
      VALUES (
        p_event_key, COALESCE(p_event_type, 'unknown'),
        v_payment.payment_id, v_order.order_id
      )
      ON CONFLICT (event_key) DO NOTHING;
      RETURN jsonb_build_object(
        'success', true,
        'ignored', true,
        'payment_already_captured', true,
        'payment_id', v_payment.payment_id,
        'order_id', v_order.order_id
      );
    END IF;

    FOR v_sib IN
      SELECT *
      FROM public.orders o
      WHERE o.order_status = 'pending'::public.order_status_enum
        AND o.auction_id IS NULL
        AND (
          o.order_id = v_order.order_id
          OR (
            v_order.checkout_group_id IS NOT NULL
            AND o.checkout_group_id = v_order.checkout_group_id
          )
        )
    LOOP
      v_void := public.void_unpaid_checkout(v_sib.order_id, true, true);
    END LOOP;
  END IF;

  INSERT INTO public.paymongo_webhook_events (
    event_key, event_type, payment_id, order_id
  )
  VALUES (
    p_event_key, COALESCE(p_event_type, 'unknown'),
    v_payment.payment_id, v_order.order_id
  )
  ON CONFLICT (event_key) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'duplicate', false,
    'paid', v_paid,
    'failed', v_failed,
    'notified', v_notified,
    'voided', COALESCE(v_void ->> 'released', 'false') = 'true',
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_paymongo_event(
  text, text, text, text, integer, text, uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paymongo_event(
  text, text, text, text, integer, text, uuid
) TO postgres, service_role;
