-- Buyer-initiated finalize after PayMongo return (failed / expired / cancel).
-- Complements apply_paymongo_event when reconcile applies void server-side.

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

  RETURN jsonb_build_object(
    'success', true,
    'outcome', CASE
      WHEN EXISTS (
        SELECT 1 FROM public.payments p
        WHERE p.order_id = p_order_id
          AND p.payment_status = 'paid'::public.payment_status_enum
      ) THEN 'paid'
      WHEN v_order.order_status = 'cancelled'::public.order_status_enum
        OR EXISTS (
          SELECT 1 FROM public.payments p
          WHERE p.order_id = p_order_id
            AND p.payment_status = 'failed'::public.payment_status_enum
        )
        OR COALESCE(v_result->>'success', 'false') = 'true' THEN
        CASE WHEN v_outcome = 'expired' THEN 'expired' ELSE 'failed' END
      ELSE 'pending'
    END,
    'void', v_result
  );
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_my_paymongo_checkout(uuid, text)
  TO authenticated, postgres, service_role;
