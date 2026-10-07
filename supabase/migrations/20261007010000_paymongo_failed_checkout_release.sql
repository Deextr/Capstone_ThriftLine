-- Release fixed-price inventory idempotently when PayMongo checkout fails.
-- Adds a guard so void_unpaid_checkout can restore stock once even if the
-- order was already cancelled without a prior restore (legacy apply path).

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_inventory_released boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.orders.checkout_inventory_released IS
  'True after checkout reservation stock was restored to the catalog/cart.';

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

  IF v_order.checkout_inventory_released THEN
    UPDATE public.payments
    SET payment_status = 'failed'::public.payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::public.payment_status_enum;
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', false,
      'released', false,
      'duplicate', true,
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
      RETURN jsonb_build_object(
        'success', true,
        'already_paid', false,
        'released', false,
        'duplicate', true,
        'order_id', v_order.order_id
      );
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;
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

    INSERT INTO public.cart_items (user_id, product_id, quantity)
    VALUES (v_order.buyer_id, v_item.product_id, v_item.quantity)
    ON CONFLICT (user_id, product_id)
    DO UPDATE SET
      quantity = GREATEST(public.cart_items.quantity, EXCLUDED.quantity),
      updated_at = now();
    v_restored_cart := true;
  END LOOP;

  UPDATE public.orders
  SET checkout_inventory_released = true
  WHERE order_id = v_order.order_id
    AND checkout_inventory_released IS DISTINCT FROM true;

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
