-- Fixed-price unpaid checkouts restore to cart instead of lingering as
-- "Awaiting Payment". Multi-shop checkouts share a checkout_group so the
-- buyer can pay once while each seller order keeps its own escrow.
-- Auction wins are unchanged: they keep payment_due_at and fallback rules.
-- Idempotent. Do not edit earlier migrations.

SET statement_timeout = '60s';

-- ===========================================================================
-- 1. Checkout groups
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.checkout_groups (
  checkout_group_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_group_id uuid;

CREATE INDEX IF NOT EXISTS orders_checkout_group_idx
  ON public.orders (checkout_group_id)
  WHERE checkout_group_id IS NOT NULL;

DO $$
BEGIN
  ALTER TABLE public.orders
    ADD CONSTRAINT orders_checkout_group_fk
    FOREIGN KEY (checkout_group_id)
    REFERENCES public.checkout_groups (checkout_group_id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

ALTER TABLE public.checkout_groups ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.checkout_groups FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.checkout_groups TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.trg_orders_assign_checkout_group()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_raw text;
  v_id uuid;
BEGIN
  IF NEW.checkout_group_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.auction_id IS NOT NULL
     OR NEW.order_type IS DISTINCT FROM 'fixed_price'::public.order_type_enum THEN
    RETURN NEW;
  END IF;

  v_raw := nullif(current_setting('thriftline.checkout_group_id', true), '');
  IF v_raw IS NOT NULL THEN
    NEW.checkout_group_id := v_raw::uuid;
    RETURN NEW;
  END IF;

  v_id := gen_random_uuid();
  INSERT INTO public.checkout_groups (checkout_group_id, buyer_id)
  VALUES (v_id, NEW.buyer_id);
  PERFORM set_config('thriftline.checkout_group_id', v_id::text, true);
  NEW.checkout_group_id := v_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_assign_checkout_group ON public.orders;
CREATE TRIGGER trg_orders_assign_checkout_group
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_assign_checkout_group();

-- ===========================================================================
-- 2. Restore unpaid fixed-price checkouts to cart
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.fixed_price_checkout_has_live_session(
  p_order_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders target
    JOIN public.orders o
      ON o.order_id = target.order_id
      OR (
        target.checkout_group_id IS NOT NULL
        AND o.checkout_group_id = target.checkout_group_id
      )
    JOIN public.payments p ON p.order_id = o.order_id
    WHERE target.order_id = p_order_id
      AND o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::public.order_type_enum
      AND p.payment_status = 'pending'::public.payment_status_enum
      AND p.checkout_session_id IS NOT NULL
      AND p.updated_at > now() - interval '15 minutes'
  );
$$;

CREATE OR REPLACE FUNCTION public.restore_my_unpaid_fixed_price_checkouts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_count integer := 0;
  r record;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT o.order_id
    FROM public.orders o
    WHERE o.buyer_id = v_buyer
      AND o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::public.order_type_enum
    FOR UPDATE OF o
  LOOP
    IF public.fixed_price_checkout_has_live_session(r.order_id) THEN
      CONTINUE;
    END IF;
    PERFORM public.void_unpaid_checkout(r.order_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.restore_my_unpaid_fixed_price_checkouts()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restore_my_unpaid_fixed_price_checkouts()
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.sync_my_unpaid_checkouts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM public.expire_unpaid_checkouts();
  PERFORM public.restore_my_unpaid_fixed_price_checkouts();
  PERFORM public.expire_auction_payment_offers();
  PERFORM public.close_auctions();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_my_unpaid_checkouts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_my_unpaid_checkouts()
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.abandon_unpaid_checkout(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_order public.orders%ROWTYPE;
  v_result jsonb;
  r record;
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

  IF v_order.checkout_group_id IS NOT NULL
     AND v_order.auction_id IS NULL THEN
    FOR r IN
      SELECT o.order_id
      FROM public.orders o
      WHERE o.checkout_group_id = v_order.checkout_group_id
        AND o.buyer_id = v_buyer
        AND o.order_status = 'pending'::public.order_status_enum
        AND o.auction_id IS NULL
    LOOP
      v_result := public.void_unpaid_checkout(r.order_id);
    END LOOP;
    RETURN COALESCE(
      v_result,
      jsonb_build_object('success', true, 'order_id', p_order_id)
    );
  END IF;

  RETURN public.void_unpaid_checkout(p_order_id);
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_unpaid_checkout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abandon_unpaid_checkout(uuid)
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.set_order_address(
  p_order_id uuid,
  p_address_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_snapshot jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order was cancelled.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.addresses a
    WHERE a.address_id = p_address_id
      AND a.user_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Choose one of your saved delivery addresses.'
    );
  END IF;

  v_snapshot := public.order_address_snapshot(p_address_id);

  UPDATE public.orders
  SET shipping_address = v_snapshot
  WHERE buyer_id = auth.uid()
    AND order_status = 'pending'::public.order_status_enum
    AND (
      order_id = p_order_id
      OR (
        v_order.checkout_group_id IS NOT NULL
        AND checkout_group_id = v_order.checkout_group_id
      )
    );

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;

-- ===========================================================================
-- 3. Combined PayMongo prepare + atomic apply
-- ===========================================================================

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
  ELSE
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
  END IF;

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_pending_order_payment(public.orders, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_pending_order_payment(public.orders, text)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.prepare_paymongo_checkout(
  p_order_id uuid,
  p_channel text DEFAULT 'gcash'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
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

REVOKE ALL ON FUNCTION public.prepare_paymongo_checkout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_paymongo_checkout(uuid, text)
  TO authenticated, postgres, service_role;

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
BEGIN
  UPDATE public.payments
  SET payment_status = 'paid'::public.payment_status_enum,
      paymongo_payment_id = COALESCE(
        NULLIF(btrim(COALESCE(p_paymongo_payment_id, '')), ''),
        paymongo_payment_id
      ),
      transaction_reference = COALESCE(
        NULLIF(btrim(COALESCE(p_session_id, '')), ''),
        transaction_reference
      )
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

REVOKE ALL ON FUNCTION public.mark_order_paid_from_payment(
  public.orders, public.payments, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_paid_from_payment(
  public.orders, public.payments, text, text
) TO postgres, service_role;

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
  v_stale_auction boolean := false;
  v_expected integer := 0;
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
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL
     AND p_paymongo_payment_id IS NOT NULL
     AND btrim(p_paymongo_payment_id) <> '' THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE paymongo_payment_id = btrim(p_paymongo_payment_id)
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL AND p_metadata_order_id IS NOT NULL THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE order_id = p_metadata_order_id
      AND payment_status = 'pending'::public.payment_status_enum
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

  IF v_paid AND v_order.auction_id IS NOT NULL THEN
    v_stale_auction :=
      v_order.order_status = 'cancelled'::public.order_status_enum
      OR (
        v_order.payment_due_at IS NOT NULL
        AND v_order.payment_due_at <= now()
      )
      OR (
        v_order.auction_offer_started_at IS NOT NULL
        AND v_payment.created_at < v_order.auction_offer_started_at
      )
      OR v_payment.payment_status = 'failed'::public.payment_status_enum;
  END IF;

  IF v_stale_auction THEN
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
    RETURN jsonb_build_object(
      'success', true,
      'ignored', true,
      'auction_window_closed', true,
      'payment_id', v_payment.payment_id,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_paid THEN
    IF v_order.order_status IN (
         'cancelled'::public.order_status_enum,
         'disputed'::public.order_status_enum
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
        'success', true, 'ignored', true, 'already_voided', true,
        'payment_id', v_payment.payment_id, 'order_id', v_order.order_id
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
      v_void := public.void_unpaid_checkout(v_sib.order_id);
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
