-- Ensure abandoning checkout always restores cart lines and reports a terminal outcome.

CREATE OR REPLACE FUNCTION public.restore_unpaid_checkout_cart_lines(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_item record;
  v_restored boolean := false;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id;

  IF NOT FOUND OR v_order.buyer_id IS NULL THEN
    RETURN false;
  END IF;

  FOR v_item IN
    SELECT product_id, quantity
    FROM public.order_items
    WHERE order_id = v_order.order_id
      AND product_id IS NOT NULL
      AND quantity > 0
  LOOP
    INSERT INTO public.cart_items (user_id, product_id, quantity)
    VALUES (v_order.buyer_id, v_item.product_id, v_item.quantity)
    ON CONFLICT (user_id, product_id)
    DO UPDATE SET
      quantity = GREATEST(public.cart_items.quantity, EXCLUDED.quantity),
      updated_at = now();
    v_restored := true;
  END LOOP;

  RETURN v_restored;
END;
$$;

REVOKE ALL ON FUNCTION public.restore_unpaid_checkout_cart_lines(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restore_unpaid_checkout_cart_lines(uuid)
  TO postgres, service_role;

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

  IF v_order.order_status = 'cancelled'::public.order_status_enum
     AND v_order.checkout_inventory_released THEN
    v_restored_cart := public.restore_unpaid_checkout_cart_lines(v_order.order_id);
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

  IF v_order.checkout_inventory_released THEN
    IF v_order.order_status = 'pending'::public.order_status_enum THEN
      UPDATE public.orders
      SET order_status = 'cancelled'::public.order_status_enum
      WHERE order_id = v_order.order_id
        AND order_status = 'pending'::public.order_status_enum;

      v_restored_cart := public.restore_unpaid_checkout_cart_lines(v_order.order_id);

      UPDATE public.payments
      SET payment_status = 'failed'::public.payment_status_enum
      WHERE order_id = v_order.order_id
        AND payment_status = 'pending'::public.payment_status_enum;

      RETURN jsonb_build_object(
        'success', true,
        'already_paid', false,
        'released', false,
        'cancelled', true,
        'cart_restored', v_restored_cart,
        'order_id', v_order.order_id
      );
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
      v_restored_cart := public.restore_unpaid_checkout_cart_lines(v_order.order_id);
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

CREATE OR REPLACE FUNCTION public.finalize_my_paymongo_checkout(
  p_order_id uuid,
  p_client_outcome text DEFAULT 'failed'
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
      v_result := public.void_unpaid_checkout(r.order_id);
    END LOOP;
  ELSE
    v_result := public.void_unpaid_checkout(p_order_id);
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

REVOKE ALL ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text)
  TO authenticated, postgres, service_role;
