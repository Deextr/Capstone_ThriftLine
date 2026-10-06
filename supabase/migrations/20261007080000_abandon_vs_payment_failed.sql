-- Abandon checkout without PayMongo must not mark payment as failed.
-- Only fail payments that started a PayMongo session (or were already failed/expired).

-- PostgreSQL cannot change arity/defaults via CREATE OR REPLACE; drop overloads first.
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid);
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid, boolean);
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid, boolean, boolean);

CREATE OR REPLACE FUNCTION public.void_unpaid_checkout(
  p_order_id uuid,
  p_restore_cart boolean DEFAULT true,
  p_treat_as_payment_failure boolean DEFAULT false
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
  v_voided integer := 0;
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
  ELSIF v_order.checkout_source = 'cart' THEN
    v_restore := COALESCE(p_restore_cart, true);
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
      v_result := public.void_unpaid_checkout(
        r.order_id,
        v_restore,
        false
      );
      v_voided := v_voided + 1;
      IF COALESCE((v_result ->> 'success')::boolean, false) IS NOT TRUE THEN
        RETURN v_result;
      END IF;
    END LOOP;

    IF v_voided = 0 THEN
      RETURN public.void_unpaid_checkout(p_order_id, v_restore, false);
    END IF;

    RETURN v_result;
  END IF;

  RETURN public.void_unpaid_checkout(p_order_id, v_restore, false);
END;
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

REVOKE ALL ON FUNCTION public.abandon_unpaid_checkout(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abandon_unpaid_checkout(uuid, boolean)
  TO authenticated, postgres, service_role;

-- PayMongo terminal failure: void with payment-failure semantics.
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
      v_result := public.void_unpaid_checkout(r.order_id, v_restore, true);
    END LOOP;
  ELSE
    v_result := public.void_unpaid_checkout(p_order_id, v_restore, true);
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
