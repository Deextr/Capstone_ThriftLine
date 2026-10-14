-- Buyer-callable idempotent auction win checkout preparation.
-- ensure_auction_order() is service-only; winners were relying on close_auctions()
-- backfill, which could fail silently while settle_one_auction still marked the
-- auction ended (order missing, stock reserved, admin sees Awaiting payment).

CREATE OR REPLACE FUNCTION public.ensure_my_auction_order(p_auction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_auction record;
  v_order_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_auction_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  SELECT a.auction_id, a.status, a.ends_at, a.winner_id
  INTO v_auction
  FROM public.auctions a
  WHERE a.auction_id = p_auction_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  IF v_auction.status = 'active'::auction_status_enum
     AND v_auction.ends_at IS NOT NULL
     AND v_auction.ends_at <= now() THEN
    BEGIN
      PERFORM public.settle_one_auction(p_auction_id, false);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'settle_one_auction failed for auction %: %', p_auction_id, SQLERRM;
    END;
    SELECT a.status, a.winner_id
    INTO v_auction
    FROM public.auctions a
    WHERE a.auction_id = p_auction_id;
  END IF;

  IF v_auction.winner_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'no_winner',
      'error', 'This auction does not have a winner yet.'
    );
  END IF;

  IF v_auction.winner_id IS DISTINCT FROM v_uid THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.auction_id = p_auction_id
        AND o.buyer_id = v_uid
        AND o.order_status = 'pending'::order_status_enum
        AND COALESCE(o.auction_offer_rank, 1) = 2
        AND o.payment_due_at IS NOT NULL
        AND o.payment_due_at > now()
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'not_eligible',
        'error', 'You are not eligible to pay for this auction.'
      );
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orders oc
    WHERE oc.auction_id = p_auction_id
      AND oc.buyer_id = v_uid
      AND oc.order_status = 'cancelled'::order_status_enum
  ) AND v_auction.winner_id IS NOT DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'payment_window_closed',
      'error', 'Your payment window for this auction has ended.'
    );
  END IF;

  BEGIN
    v_order_id := public.ensure_auction_order(p_auction_id);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'ensure_auction_order failed for auction %: %', p_auction_id, SQLERRM;
      v_order_id := NULL;
  END;

  IF v_order_id IS NULL THEN
    SELECT o.order_id
    INTO v_order_id
    FROM public.orders o
    WHERE o.auction_id = p_auction_id
      AND o.buyer_id = v_uid
      AND o.order_status = 'pending'::order_status_enum
      AND (
        o.payment_due_at IS NULL
        OR o.payment_due_at > now()
      )
    ORDER BY o.created_at DESC
    LIMIT 1;
  END IF;

  IF v_order_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'order_not_ready',
      'error',
      'We could not prepare your order yet. Please try again in a moment.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_auction_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_auction_order(uuid)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.ensure_my_auction_order(uuid) IS
  'Winner or second-chance buyer: settle ended auction if needed and return pending order_id.';

-- Heal pending winner orders missing line items (buyer could not pay; admin still saw order).
CREATE OR REPLACE FUNCTION public.ensure_auction_order(p_auction_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auction record;
  v_product record;
  v_existing public.orders%ROWTYPE;
  v_order_id uuid;
  v_price numeric(12, 2);
  v_platform numeric(12, 2);
  v_shipping numeric(12, 2);
  v_total numeric(12, 2);
  v_address_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_image text;
  v_name text;
BEGIN
  IF p_auction_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT a.auction_id, a.product_id, a.winner_id, a.winning_bid_id,
         a.current_price, a.status, a.bid_round
  INTO v_auction
  FROM public.auctions a
  WHERE a.auction_id = p_auction_id
  FOR UPDATE;

  IF NOT FOUND OR v_auction.winner_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT p.product_id, p.seller_id, p.name, p.size, p.status
  INTO v_product
  FROM public.products p
  WHERE p.product_id = v_auction.product_id
  FOR UPDATE;

  IF NOT FOUND OR v_product.seller_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_product.seller_id = v_auction.winner_id THEN
    RETURN NULL;
  END IF;

  SELECT t.subtotal, t.shipping_fee, t.platform_fee, t.total_amount
  INTO v_price, v_shipping, v_platform, v_total
  FROM public.auction_checkout_total(v_auction.current_price, v_product.product_id) t;

  SELECT a.address_id INTO v_address_id
  FROM public.addresses a
  WHERE a.user_id = v_auction.winner_id
  ORDER BY a.is_default DESC, a.created_at DESC
  LIMIT 1;

  IF v_address_id IS NOT NULL THEN
    v_snapshot := public.order_address_snapshot(v_address_id);
  END IF;

  SELECT pi.image_url INTO v_image
  FROM public.product_images pi
  WHERE pi.product_id = v_product.product_id
  ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
  LIMIT 1;

  v_name := COALESCE(NULLIF(btrim(v_product.name), ''), 'this item');

  SELECT * INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id
  FOR UPDATE;

  IF v_existing.order_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.payments pay
      WHERE pay.order_id = v_existing.order_id
        AND pay.payment_status = 'paid'::payment_status_enum
    ) THEN
      RETURN v_existing.order_id;
    END IF;

    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'pending'::order_status_enum
       AND v_existing.payment_due_at IS NOT NULL
       AND v_existing.payment_due_at > now() THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.order_items oi
        WHERE oi.order_id = v_existing.order_id
      ) THEN
        INSERT INTO public.order_items (
          order_id, product_id, auction_id, title, image_url, size,
          unit_price, quantity, line_total
        )
        VALUES (
          v_existing.order_id, v_product.product_id, p_auction_id, v_name, v_image,
          v_product.size, v_price, 1, v_price
        );
      END IF;
      RETURN v_existing.order_id;
    END IF;

    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'cancelled'::order_status_enum THEN
      RETURN NULL;
    END IF;

    UPDATE public.payments
    SET payment_status = 'failed'::payment_status_enum
    WHERE order_id = v_existing.order_id
      AND payment_status = 'pending'::payment_status_enum;

    UPDATE public.orders
    SET buyer_id = v_auction.winner_id,
        seller_id = v_product.seller_id,
        order_status = 'pending'::order_status_enum,
        subtotal = v_price,
        shipping_fee = v_shipping,
        platform_fee = v_platform,
        total_amount = v_total,
        shipping_address = v_snapshot,
        payment_due_at = now() + interval '12 hours',
        auction_offer_rank = 1,
        passed_bidder_id = NULL,
        auction_offer_started_at = now(),
        updated_at = now()
    WHERE order_id = v_existing.order_id;

    UPDATE public.order_items
    SET product_id = v_product.product_id,
        title = v_name,
        image_url = v_image,
        unit_price = v_price,
        line_total = v_price,
        size = v_product.size,
        updated_at = now()
    WHERE order_id = v_existing.order_id;

    IF NOT FOUND THEN
      INSERT INTO public.order_items (
        order_id, product_id, auction_id, title, image_url, size,
        unit_price, quantity, line_total
      )
      VALUES (
        v_existing.order_id, v_product.product_id, p_auction_id, v_name, v_image,
        v_product.size, v_price, 1, v_price
      );
    END IF;

    PERFORM public.reserve_auction_unit(v_product.product_id);

    RETURN v_existing.order_id;
  END IF;

  INSERT INTO public.orders (
    order_number, buyer_id, seller_id, auction_id, order_type, order_status,
    subtotal, shipping_fee, platform_fee, total_amount, shipping_address,
    payment_due_at, auction_offer_rank, auction_offer_started_at
  )
  VALUES (
    public.next_order_number(),
    v_auction.winner_id,
    v_product.seller_id,
    p_auction_id,
    'auction'::order_type_enum,
    'pending'::order_status_enum,
    v_price,
    v_shipping,
    v_platform,
    v_total,
    v_snapshot,
    now() + interval '12 hours',
    1,
    now()
  )
  ON CONFLICT (auction_id) WHERE auction_id IS NOT NULL DO NOTHING
  RETURNING order_id INTO v_order_id;

  IF v_order_id IS NULL THEN
    SELECT o.order_id INTO v_order_id
    FROM public.orders o
    WHERE o.auction_id = p_auction_id;
    RETURN v_order_id;
  END IF;

  INSERT INTO public.order_items (
    order_id, product_id, auction_id, title, image_url, size,
    unit_price, quantity, line_total
  )
  VALUES (
    v_order_id, v_product.product_id, p_auction_id, v_name, v_image,
    v_product.size, v_price, 1, v_price
  );

  PERFORM public.reserve_auction_unit(v_product.product_id);

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_auction_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_auction_order(uuid) TO postgres, service_role;
