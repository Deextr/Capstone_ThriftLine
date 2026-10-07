-- Fix unpaid checkout void/abandon: never cancel without restoring reserved stock.
-- Clears stale checkout_inventory_released on still-pending orders so stock restore runs.

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

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(
  p_order_id uuid,
  p_restore_cart boolean DEFAULT true
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

  -- Stale flag: pending checkout must still release reserved stock once.
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
    UPDATE public.payments
    SET payment_status = 'failed'::public.payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::public.payment_status_enum;
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'duplicate', true,
      'cart_restored', v_restored_cart,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum THEN
    NULL;
  ELSE
    UPDATE public.orders
    SET order_status = 'cancelled'::public.order_status_enum
    WHERE order_id = v_order.order_id
      AND order_status = 'pending'::public.order_status_enum;

    IF NOT FOUND THEN
      IF v_order.checkout_inventory_released THEN
        IF v_restore_cart THEN
          v_restored_cart := public.restore_unpaid_checkout_cart_lines(v_order.order_id);
        END IF;
        UPDATE public.payments
        SET payment_status = 'failed'::public.payment_status_enum
        WHERE order_id = v_order.order_id
          AND payment_status = 'pending'::public.payment_status_enum;
        RETURN jsonb_build_object(
          'success', true,
          'already_paid', false,
          'released', false,
          'duplicate', true,
          'cart_restored', v_restored_cart,
          'order_id', v_order.order_id
        );
      END IF;

      SELECT * INTO v_order
      FROM public.orders
      WHERE order_id = p_order_id
      FOR UPDATE;

      IF v_order.order_status <> 'cancelled'::public.order_status_enum THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'Unable to cancel this checkout.',
          'order_id', v_order.order_id
        );
      END IF;
    ELSE
      SELECT * INTO v_order
      FROM public.orders
      WHERE order_id = p_order_id
      FOR UPDATE;
    END IF;
  END IF;

  v_released := true;

  UPDATE public.payments
  SET payment_status = 'failed'::public.payment_status_enum
  WHERE order_id = v_order.order_id
    AND payment_status = 'pending'::public.payment_status_enum;

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

  IF v_restore_cart THEN
    PERFORM public.notify_user(
      v_order.buyer_id,
      'system',
      'Payment failed',
      'Your purchase was not completed. The item remains in your cart.',
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

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'released', v_released,
    'cancelled', true,
    'cart_restored', v_restored_cart,
    'order_id', v_order.order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  TO postgres, service_role;

-- One-arg overload for legacy callers (restore cart unless buy_now on order row).
CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(p_order_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.void_unpaid_checkout(p_order_id, true);
$$;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid)
  TO postgres, service_role;

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
    PERFORM public.void_unpaid_checkout(r.order_id, true);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
