-- Checkout lifecycle fixes:
-- 1) Inventory restoration must not enforce seller active-listing cap (internal op).
-- 2) void_unpaid_checkout(uuid) ambiguity (42725): 3-arg core without DEFAULTs + SQL wrappers.
-- 3) PayMongo failure voids mark payment failed; stale cleanup uses explicit 3-arg calls.

-- ===========================================================================
-- 1. Skip listing cap for system inventory restoration (not seller publish)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trg_products_enforce_active_listing_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.seller_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF current_setting('thriftline.skip_seller_listing_limit', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'active'::public.product_status_enum
     AND (
       TG_OP = 'INSERT'
       OR OLD.status IS DISTINCT FROM 'active'::public.product_status_enum
     )
  THEN
    PERFORM public.assert_seller_active_listing_capacity(
      NEW.seller_id,
      NEW.product_id
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_product_stock(
  p_product_id uuid,
  p_quantity integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new_qty integer;
BEGIN
  IF p_product_id IS NULL OR COALESCE(p_quantity, 0) < 1 THEN
    RETURN;
  END IF;

  SELECT quantity_available + p_quantity
  INTO v_new_qty
  FROM public.products
  WHERE product_id = p_product_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM set_config('thriftline.skip_seller_listing_limit', 'on', true);

  UPDATE public.products
  SET quantity_available = v_new_qty,
      status = CASE
        WHEN v_new_qty > 0 THEN 'active'::public.product_status_enum
        ELSE status
      END,
      sold_at = CASE
        WHEN v_new_qty > 0 THEN NULL
        ELSE sold_at
      END
  WHERE product_id = p_product_id;
END;
$$;

COMMENT ON FUNCTION public.restore_product_stock(uuid, integer) IS
  'Restores reserved checkout stock. Bypasses seller active-listing cap (not a publish).';

-- ===========================================================================
-- 2. void_unpaid_checkout — single 3-arg implementation, wrapper overloads only
-- ===========================================================================

DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid);
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid, boolean);
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid, boolean, boolean);

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(
  p_order_id uuid,
  p_restore_cart boolean,
  p_treat_as_payment_failure boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_item record;
  v_released boolean := false;
  v_restored_cart boolean := false;
  v_restore_cart boolean := COALESCE(p_restore_cart, true);
BEGIN
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

  IF v_order.checkout_source = 'buy_now' THEN
    v_restore_cart := false;
  END IF;

  IF v_order.order_status = 'paid'::public.order_status_enum
     OR EXISTS (
       SELECT 1 FROM public.payments p
       WHERE p.order_id = v_order.order_id
         AND p.payment_status = 'paid'::public.payment_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'released', false,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_order.auction_id IS NOT NULL
     OR v_order.order_type = 'auction'::public.order_type_enum THEN
    UPDATE public.payments
    SET payment_status = 'failed'::public.payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::public.payment_status_enum;
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'auction', true,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_order.order_status = 'pending'::public.order_status_enum
     AND v_order.checkout_inventory_released THEN
    UPDATE public.orders
    SET checkout_inventory_released = false
    WHERE order_id = p_order_id;
    v_order.checkout_inventory_released := false;
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum
     AND v_order.checkout_inventory_released THEN
    IF v_restore_cart THEN
      v_restored_cart := public.restore_unpaid_checkout_cart_lines(v_order.order_id);
    END IF;
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'duplicate', true,
      'cart_restored', v_restored_cart,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum
     AND NOT v_order.checkout_inventory_released THEN
    NULL;
  ELSIF v_order.order_status = 'pending'::public.order_status_enum THEN
    UPDATE public.orders
    SET order_status = 'cancelled'::public.order_status_enum
    WHERE order_id = v_order.order_id
      AND order_status = 'pending'::public.order_status_enum;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Unable to cancel this checkout.',
        'order_id', v_order.order_id
      );
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This checkout can no longer be cancelled.',
      'order_id', v_order.order_id,
      'order_status', v_order.order_status::text
    );
  END IF;

  v_released := true;

  IF COALESCE(p_treat_as_payment_failure, false) THEN
    UPDATE public.payments
    SET payment_status = 'failed'::public.payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::public.payment_status_enum;
  ELSE
    UPDATE public.payments
    SET payment_status = 'failed'::public.payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::public.payment_status_enum
      AND checkout_session_id IS NOT NULL;
  END IF;

  FOR v_item IN
    SELECT product_id, quantity
    FROM public.order_items
    WHERE order_id = v_order.order_id
      AND product_id IS NOT NULL
      AND quantity > 0
  LOOP
    PERFORM public.restore_product_stock(v_item.product_id, v_item.quantity);

    IF v_restore_cart THEN
      INSERT INTO public.cart_items (user_id, product_id, quantity)
      VALUES (v_order.buyer_id, v_item.product_id, v_item.quantity)
      ON CONFLICT (user_id, product_id)
      DO UPDATE SET
        quantity = GREATEST(public.cart_items.quantity, EXCLUDED.quantity),
        updated_at = now();
      v_restored_cart := true;
    END IF;
  END LOOP;

  UPDATE public.orders
  SET checkout_inventory_released = true
  WHERE order_id = v_order.order_id
    AND checkout_inventory_released IS DISTINCT FROM true;

  BEGIN
    IF COALESCE(p_treat_as_payment_failure, false) THEN
      PERFORM public.notify_user(
        v_order.buyer_id,
        'system',
        'Payment failed',
        'Your purchase was not completed. The item remains in your cart.',
        jsonb_build_object('order_id', v_order.order_id)
      );
    ELSIF v_restore_cart THEN
      PERFORM public.notify_user(
        v_order.buyer_id,
        'system',
        'Checkout cancelled',
        'Your checkout was cancelled. The item remains in your cart.',
        jsonb_build_object('order_id', v_order.order_id)
      );
    ELSE
      PERFORM public.notify_user(
        v_order.buyer_id,
        'system',
        'Checkout cancelled',
        'Your checkout was cancelled. The listing is still available.',
        jsonb_build_object('order_id', v_order.order_id)
      );
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'released', v_released,
    'cancelled', true,
    'abandoned', NOT COALESCE(p_treat_as_payment_failure, false),
    'cart_restored', v_restored_cart,
    'order_id', v_order.order_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(p_order_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.void_unpaid_checkout(p_order_id, true, false);
$$;

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(
  p_order_id uuid,
  p_restore_cart boolean
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.void_unpaid_checkout(p_order_id, p_restore_cart, false);
$$;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid, boolean, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid, boolean, boolean)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid)
  TO postgres, service_role;

-- ===========================================================================
-- 3. Call sites — explicit 3-arg where needed
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.expire_unpaid_checkouts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
  r record;
BEGIN
  FOR r IN
    SELECT o.order_id
    FROM public.orders o
    WHERE o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::public.order_type_enum
      AND o.created_at < now() - interval '90 minutes'
  LOOP
    PERFORM public.void_unpaid_checkout(r.order_id, true, false);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
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
    PERFORM public.void_unpaid_checkout(r.order_id, true, false);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

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
