-- Track buy-now vs cart checkout on orders; optional cart restore on abandon.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_source text;

COMMENT ON COLUMN public.orders.checkout_source IS
  'buy_now or cart — how the fixed-price checkout was started.';

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_checkout_source_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_checkout_source_check
  CHECK (
    checkout_source IS NULL
    OR checkout_source IN ('buy_now', 'cart')
  );

CREATE OR REPLACE FUNCTION public.set_my_order_checkout_source(
  p_order_id uuid,
  p_checkout_source text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_order public.orders%ROWTYPE;
  v_source text := lower(btrim(COALESCE(p_checkout_source, '')));
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF v_source NOT IN ('buy_now', 'cart') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid checkout source.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.auction_id IS NOT NULL
     OR v_order.order_type = 'auction'::public.order_type_enum THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  UPDATE public.orders o
  SET checkout_source = v_source
  WHERE o.buyer_id = v_buyer
    AND o.order_status = 'pending'::public.order_status_enum
    AND o.auction_id IS NULL
    AND (
      o.order_id = p_order_id
      OR (
        v_order.checkout_group_id IS NOT NULL
        AND o.checkout_group_id = v_order.checkout_group_id
      )
    );

  RETURN jsonb_build_object('success', true, 'checkout_source', v_source);
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_order_checkout_source(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_order_checkout_source(uuid, text)
  TO authenticated, postgres, service_role;

DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid);

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

  IF v_order.checkout_inventory_released THEN
    IF v_order.order_status = 'pending'::public.order_status_enum THEN
      UPDATE public.orders
      SET order_status = 'cancelled'::public.order_status_enum
      WHERE order_id = v_order.order_id
        AND order_status = 'pending'::public.order_status_enum;

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
    'cart_restored', v_restored_cart,
    'order_id', v_order.order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_unpaid_checkout(uuid, boolean)
  TO postgres, service_role;

DROP FUNCTION IF EXISTS public.abandon_unpaid_checkout(uuid);

CREATE OR REPLACE FUNCTION public.abandon_unpaid_checkout(
  p_order_id uuid,
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
  v_result jsonb;
  v_restore boolean := COALESCE(p_restore_cart, true);
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

  IF v_order.checkout_source = 'buy_now' THEN
    v_restore := false;
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
      v_result := public.void_unpaid_checkout(r.order_id, v_restore);
    END LOOP;
    RETURN COALESCE(
      v_result,
      jsonb_build_object('success', true, 'order_id', p_order_id)
    );
  END IF;

  RETURN public.void_unpaid_checkout(p_order_id, v_restore);
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_unpaid_checkout(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abandon_unpaid_checkout(uuid, boolean)
  TO authenticated, postgres, service_role;

DROP FUNCTION IF EXISTS public.finalize_my_paymongo_checkout(uuid, text);

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
      v_result := public.void_unpaid_checkout(r.order_id, v_restore);
    END LOOP;
  ELSE
    v_result := public.void_unpaid_checkout(p_order_id, v_restore);
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
