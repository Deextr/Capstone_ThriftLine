-- Phase 6 revision — mandatory payment.
-- Treats Phase 5 checkout stock deduction as a reservation:
--   success webhook  → keep deduction, mark paid
--   fail/expire/void → restore stock + cart once, cancel unpaid fixed-price order
-- Auction-win orders are not auto-voided (unique auction_id / winner policy).
-- Does not rewrite previously applied migrations.

-- ===========================================================================
-- 1. Distinguish PayMongo channel without implying a direct GCash API
-- ===========================================================================

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS paymongo_channel text;

ALTER TABLE public.payments
  DROP CONSTRAINT IF EXISTS payments_paymongo_channel_chk;

ALTER TABLE public.payments
  ADD CONSTRAINT payments_paymongo_channel_chk
  CHECK (
    paymongo_channel IS NULL
    OR paymongo_channel IN ('card', 'gcash')
  );

-- ===========================================================================
-- 2. restore_product_stock — inverse of consume_product_stock, once-safe
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.restore_product_stock(
  p_product_id uuid,
  p_quantity integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_product_id IS NULL OR COALESCE(p_quantity, 0) < 1 THEN
    RETURN;
  END IF;

  UPDATE public.products
  SET quantity_available = quantity_available + p_quantity,
      status = CASE
        WHEN status = 'sold'::product_status_enum
             AND quantity_available + p_quantity > 0
          THEN 'active'::product_status_enum
        ELSE status
      END,
      sold_at = CASE
        WHEN status = 'sold'::product_status_enum
             AND quantity_available + p_quantity > 0
          THEN NULL
        ELSE sold_at
      END
  WHERE product_id = p_product_id;
END;
$$;

REVOKE ALL ON FUNCTION public.restore_product_stock(uuid, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restore_product_stock(uuid, integer)
  TO postgres, service_role;

-- ===========================================================================
-- 3. void_unpaid_checkout — idempotent reservation release
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(p_order_id uuid)
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

  IF v_order.order_status = 'paid'::order_status_enum
     OR EXISTS (
       SELECT 1 FROM public.payments p
       WHERE p.order_id = v_order.order_id
         AND p.payment_status = 'paid'::payment_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'released', false,
      'order_id', v_order.order_id
    );
  END IF;

  -- Auction wins keep the reservation. Documented separately.
  IF v_order.auction_id IS NOT NULL
     OR v_order.order_type = 'auction'::order_type_enum THEN
    UPDATE public.payments
    SET payment_status = 'failed'::payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::payment_status_enum;
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'auction', true,
      'order_id', v_order.order_id
    );
  END IF;

  UPDATE public.orders
  SET order_status = 'cancelled'::order_status_enum
  WHERE order_id = v_order.order_id
    AND order_status = 'pending'::order_status_enum;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'duplicate', true,
      'order_id', v_order.order_id
    );
  END IF;

  v_released := true;

  UPDATE public.payments
  SET payment_status = 'failed'::payment_status_enum
  WHERE order_id = v_order.order_id
    AND payment_status = 'pending'::payment_status_enum;

  FOR v_item IN
    SELECT product_id, quantity
    FROM public.order_items
    WHERE order_id = v_order.order_id
      AND product_id IS NOT NULL
      AND quantity > 0
  LOOP
    PERFORM public.restore_product_stock(v_item.product_id, v_item.quantity);

    INSERT INTO public.cart_items (user_id, product_id, quantity)
    VALUES (v_order.buyer_id, v_item.product_id, v_item.quantity)
    ON CONFLICT (user_id, product_id)
    DO UPDATE SET
      quantity = GREATEST(public.cart_items.quantity, EXCLUDED.quantity),
      updated_at = now();
    v_restored_cart := true;
  END LOOP;

  PERFORM public.notify_user(
    v_order.buyer_id,
    'system',
    'Payment failed',
    'Your purchase was not completed. The item remains in your cart.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'released', v_released,
    'cart_restored', v_restored_cart,
    'order_id', v_order.order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.abandon_unpaid_checkout(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_order public.orders%ROWTYPE;
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

  RETURN public.void_unpaid_checkout(p_order_id);
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_unpaid_checkout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abandon_unpaid_checkout(uuid)
  TO authenticated, postgres, service_role;

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
    WHERE o.order_status = 'pending'::order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::order_type_enum
      AND o.created_at < now() - interval '90 minutes'
  LOOP
    PERFORM public.void_unpaid_checkout(r.order_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_unpaid_checkouts()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_unpaid_checkouts()
  TO postgres, service_role;

-- ===========================================================================
-- 4. prepare_paymongo_checkout(order_id, channel)
-- ===========================================================================

DROP FUNCTION IF EXISTS public.prepare_paymongo_checkout(uuid);

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
  v_payment public.payments%ROWTYPE;
  v_centavos integer;
  v_reuse boolean := false;
  v_channel text;
BEGIN
  PERFORM public.expire_unpaid_checkouts();

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

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status = 'cancelled'::order_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This checkout was not completed. The item is back in your cart.'
    );
  END IF;

  IF v_order.order_status = 'disputed'::order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order cannot be paid.');
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum THEN
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
      AND p.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number
    );
  END IF;

  v_centavos := round(v_order.total_amount * 100)::integer;
  IF v_centavos IS NULL OR v_centavos < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order has no payable amount.');
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = v_order.order_id
    AND payment_status = 'pending'::payment_status_enum
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.payments
    SET total_amount = v_order.total_amount,
        amount_centavos = v_centavos,
        currency = 'PHP',
        payment_method = 'paymongo'::payment_method_enum,
        paymongo_channel = v_channel
    WHERE payment_id = v_payment.payment_id
    RETURNING * INTO v_payment;

    IF v_payment.checkout_session_id IS NOT NULL
       AND v_payment.checkout_url IS NOT NULL
       AND v_payment.paymongo_channel IS NOT DISTINCT FROM v_channel
       AND v_payment.updated_at > now() - interval '15 minutes' THEN
      v_reuse := true;
    END IF;
  ELSE
    INSERT INTO public.payments (
      order_id,
      payment_method,
      total_amount,
      payment_status,
      amount_centavos,
      currency,
      paymongo_channel
    )
    VALUES (
      v_order.order_id,
      'paymongo'::payment_method_enum,
      v_order.total_amount,
      'pending'::payment_status_enum,
      v_centavos,
      'PHP',
      v_channel
    )
    RETURNING * INTO v_payment;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'reuse', v_reuse,
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id,
    'order_number', v_order.order_number,
    'total_amount', v_order.total_amount,
    'amount_centavos', v_centavos,
    'currency', 'PHP',
    'channel', v_channel,
    'checkout_url', CASE WHEN v_reuse THEN v_payment.checkout_url ELSE NULL END,
    'session_id', CASE WHEN v_reuse THEN v_payment.checkout_session_id ELSE NULL END,
    'previous_session_id', CASE WHEN v_reuse THEN NULL ELSE v_payment.checkout_session_id END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_paymongo_checkout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_paymongo_checkout(uuid, text)
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 5. apply_paymongo_event — paid finalizes; fail/expire voids reservation
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
  v_paid boolean := false;
  v_failed boolean := false;
  v_notified boolean := false;
  v_currency text;
  v_void jsonb;
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

  v_paid := p_event_type IN (
    'checkout_session.payment.paid',
    'payment.paid'
  );
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
      AND payment_status = 'pending'::payment_status_enum
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

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF p_metadata_order_id IS NOT NULL
     AND p_metadata_order_id IS DISTINCT FROM v_order.order_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order mismatch.');
  END IF;

  v_currency := upper(COALESCE(NULLIF(btrim(p_currency), ''), 'PHP'));
  IF v_currency IS DISTINCT FROM 'PHP' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Currency mismatch.');
  END IF;

  IF v_paid THEN
    IF v_order.order_status IN (
         'cancelled'::order_status_enum,
         'disputed'::order_status_enum
       ) THEN
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
        'already_voided', true,
        'payment_id', v_payment.payment_id,
        'order_id', v_order.order_id
      );
    END IF;

    IF p_amount_centavos IS NULL
       OR p_amount_centavos IS DISTINCT FROM v_payment.amount_centavos THEN
      RETURN jsonb_build_object('success', false, 'error', 'Amount mismatch.');
    END IF;

    UPDATE public.payments
    SET payment_status = 'paid'::payment_status_enum,
        paymongo_payment_id = COALESCE(
          NULLIF(btrim(COALESCE(p_paymongo_payment_id, '')), ''),
          paymongo_payment_id
        ),
        transaction_reference = COALESCE(
          NULLIF(btrim(COALESCE(p_session_id, '')), ''),
          transaction_reference
        )
    WHERE payment_id = v_payment.payment_id
      AND payment_status IS DISTINCT FROM 'paid'::payment_status_enum;

    IF v_order.order_status = 'pending'::order_status_enum THEN
      UPDATE public.orders
      SET order_status = 'paid'::order_status_enum
      WHERE order_id = v_order.order_id
        AND order_status = 'pending'::order_status_enum;

      IF FOUND THEN
        PERFORM public.notify_user(
          v_order.buyer_id,
          'orderConfirmed',
          'Payment successful',
          CASE
            WHEN v_payment.paymongo_channel = 'gcash'
              THEN 'Your GCash payment has been received. Order #'
            ELSE 'Your card payment has been received. Order #'
          END || COALESCE(v_order.order_number, '') || ' is paid.',
          jsonb_build_object('order_id', v_order.order_id)
        );
        PERFORM public.notify_user(
          v_order.seller_id,
          'system',
          'New paid order',
          'A buyer has completed payment for Order #' ||
            COALESCE(v_order.order_number, '') || '.',
          jsonb_build_object('order_id', v_order.order_id)
        );
        v_notified := true;
      END IF;
    END IF;
  ELSIF v_failed THEN
    v_void := public.void_unpaid_checkout(v_order.order_id);
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

-- ===========================================================================
-- 6. checkout_cart — one seller per checkout, no unpaid "order placed" notify
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.checkout_cart(
  p_address_id uuid,
  p_product_id uuid DEFAULT NULL,
  p_quantity integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_address public.addresses%ROWTYPE;
  v_snapshot jsonb;
  v_seller uuid;
  v_order_id uuid;
  v_subtotal numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_created integer := 0;
  r record;
  v_avail integer;
  v_status product_status_enum;
  v_type listing_type_enum;
  v_price numeric(12, 2);
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to check out.');
  END IF;

  IF p_address_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Add a delivery address before checkout.');
  END IF;

  SELECT * INTO v_address
  FROM public.addresses
  WHERE address_id = p_address_id
    AND user_id = v_buyer;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
  END IF;

  v_snapshot := public.order_address_snapshot(p_address_id);

  PERFORM pg_advisory_xact_lock(hashtext(v_buyer::text));

  CREATE TEMP TABLE IF NOT EXISTS tmp_checkout_lines (
    product_id uuid PRIMARY KEY,
    seller_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    title text NOT NULL,
    image_url text,
    size text
  ) ON COMMIT DROP;

  DELETE FROM tmp_checkout_lines WHERE TRUE;

  IF p_product_id IS NOT NULL THEN
    INSERT INTO tmp_checkout_lines (
      product_id, seller_id, quantity, unit_price, title, image_url, size
    )
    SELECT
      p.product_id,
      p.seller_id,
      c.quantity,
      p.price,
      COALESCE(NULLIF(btrim(p.name), ''), 'Listing'),
      (
        SELECT pi.image_url
        FROM public.product_images pi
        WHERE pi.product_id = p.product_id
        ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
        LIMIT 1
      ),
      p.size
    FROM public.products p
    JOIN public.cart_items c
      ON c.product_id = p.product_id AND c.user_id = v_buyer
    WHERE p.product_id = p_product_id
      AND p.listing_type = 'fixed_price'::listing_type_enum
      AND p.status = 'active'::product_status_enum;

    IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Add this item to your cart before checkout.'
      );
    END IF;
  ELSE
    INSERT INTO tmp_checkout_lines (
      product_id, seller_id, quantity, unit_price, title, image_url, size
    )
    SELECT
      p.product_id,
      p.seller_id,
      c.quantity,
      p.price,
      COALESCE(NULLIF(btrim(p.name), ''), 'Listing'),
      (
        SELECT pi.image_url
        FROM public.product_images pi
        WHERE pi.product_id = p.product_id
        ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
        LIMIT 1
      ),
      p.size
    FROM public.cart_items c
    JOIN public.products p ON p.product_id = c.product_id
    WHERE c.user_id = v_buyer
      AND p.listing_type = 'fixed_price'::listing_type_enum
      AND p.status = 'active'::product_status_enum
      AND p.seller_id IS DISTINCT FROM v_buyer;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your cart has no items that can be checked out.'
    );
  END IF;

  -- One seller per payment session. Other sellers stay in the cart.
  DELETE FROM tmp_checkout_lines
  WHERE seller_id IS DISTINCT FROM (
    SELECT t.seller_id
    FROM tmp_checkout_lines t
    ORDER BY t.seller_id
    LIMIT 1
  );

  PERFORM 1
  FROM public.products p
  JOIN tmp_checkout_lines t ON t.product_id = p.product_id
  FOR UPDATE OF p;

  FOR r IN SELECT * FROM tmp_checkout_lines
  LOOP
    IF r.seller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'A listing is missing its seller.');
    END IF;
    IF r.seller_id = v_buyer THEN
      RETURN jsonb_build_object('success', false, 'error', 'You cannot purchase your own listing.');
    END IF;

    SELECT p.quantity_available, p.status, p.listing_type, p.price
    INTO v_avail, v_status, v_type, v_price
    FROM public.products p
    WHERE p.product_id = r.product_id;

    IF v_status IS DISTINCT FROM 'active'::product_status_enum
       OR v_type IS DISTINCT FROM 'fixed_price'::listing_type_enum THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', COALESCE(r.title, 'This item') || ' is no longer available.'
      );
    END IF;

    IF v_price IS DISTINCT FROM r.unit_price THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'The price of ' || COALESCE(r.title, 'this item') ||
          ' has changed. Refresh your cart.'
      );
    END IF;

    IF COALESCE(v_avail, 0) < r.quantity THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Available stock has changed. Only ' ||
          COALESCE(v_avail, 0)::text || ' left of ' ||
          COALESCE(r.title, 'this item') ||
          '. Update the quantity and try again.'
      );
    END IF;
  END LOOP;

  FOR v_seller IN
    SELECT DISTINCT seller_id FROM tmp_checkout_lines ORDER BY seller_id
  LOOP
    SELECT COALESCE(sum(quantity * unit_price), 0)
    INTO v_subtotal
    FROM tmp_checkout_lines
    WHERE seller_id = v_seller;

    v_shipping := 80;
    v_platform := round(v_subtotal * 0.02, 2);
    v_total := v_subtotal + v_shipping + v_platform;

    INSERT INTO public.orders (
      order_number,
      buyer_id,
      seller_id,
      order_type,
      order_status,
      subtotal,
      shipping_fee,
      platform_fee,
      total_amount,
      shipping_address
    )
    VALUES (
      public.next_order_number(),
      v_buyer,
      v_seller,
      'fixed_price'::order_type_enum,
      'pending'::order_status_enum,
      v_subtotal,
      v_shipping,
      v_platform,
      v_total,
      v_snapshot
    )
    RETURNING order_id INTO v_order_id;

    INSERT INTO public.order_items (
      order_id, product_id, title, image_url, size, unit_price, quantity, line_total
    )
    SELECT
      v_order_id,
      t.product_id,
      t.title,
      t.image_url,
      t.size,
      t.unit_price,
      t.quantity,
      round(t.unit_price * t.quantity, 2)
    FROM tmp_checkout_lines t
    WHERE t.seller_id = v_seller;

    FOR r IN SELECT product_id, quantity, title FROM tmp_checkout_lines WHERE seller_id = v_seller
    LOOP
      PERFORM public.consume_product_stock(r.product_id, r.quantity);
    END LOOP;

    v_order_ids := array_append(v_order_ids, v_order_id);
    v_created := v_created + 1;
  END LOOP;

  DELETE FROM public.cart_items c
  USING tmp_checkout_lines t
  WHERE c.user_id = v_buyer
    AND c.product_id = t.product_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_order_ids),
    'order_id', v_order_ids[1],
    'count', v_created
  );
END;
$$;

REVOKE ALL ON FUNCTION public.checkout_cart(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkout_cart(uuid, uuid, integer)
  TO authenticated, postgres, service_role;
