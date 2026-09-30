-- Migration: 20260930140000_fix_auction_system.sql
--
-- Fixes for the auction/bidding system:
--
-- 1. ensure_auction_order:
--    BUG FIX — Don't regenerate a 12-hour payment window if the original
--    order was already cancelled (buyer's payment deadline expired). Before
--    this fix, close_auctions() would call ensure_auction_order() on every
--    page load, giving the expired buyer an infinite stream of fresh 12-hour
--    windows.
--
-- 2. close_auctions:
--    BUG FIX — Skip calling ensure_auction_order for ended auctions where
--    the winner's order has already been cancelled (payment expired). This
--    avoids the unnecessary function call and aligns with (1).
--
-- 3. relist_unsold_auction:
--    FEATURE — Accept optional p_starting_price and p_minimum_increment so
--    the seller can adjust auction details when relisting, not just duration.

-- ===========================================================================
-- 1. ensure_auction_order: don't regenerate cancelled-expired orders
-- ===========================================================================

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
  FROM public.auction_checkout_total(v_auction.current_price) t;

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

  -- Check if an order already exists for this auction
  SELECT * INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id
  FOR UPDATE;

  IF v_existing.order_id IS NOT NULL THEN
    -- If already paid, leave it alone
    IF EXISTS (
      SELECT 1 FROM public.payments pay
      WHERE pay.order_id = v_existing.order_id
        AND pay.payment_status = 'paid'::payment_status_enum
    ) THEN
      RETURN v_existing.order_id;
    END IF;

    -- If already pending for the current winner and payment window is still valid, return it
    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'pending'::order_status_enum
       AND v_existing.payment_due_at IS NOT NULL
       AND v_existing.payment_due_at > now() THEN
      RETURN v_existing.order_id;
    END IF;

    -- *** BUG FIX ***
    -- If the existing order was cancelled for this same winner (payment expired),
    -- do NOT create a new 12-hour window. The seller must offer to the next
    -- bidder or relist. Without this check, close_auctions() would infinitely
    -- regenerate fresh payment windows on every page load.
    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'cancelled'::order_status_enum THEN
      RETURN NULL;
    END IF;

    -- Otherwise, refresh this order for the current winner with a fresh 12-hour window
    -- (This path is used by offer_auction_to_next_bidder which changes winner_id)
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

  -- Create brand new order if none exists
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

-- ===========================================================================
-- 2. close_auctions: skip expired-payment winners
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.close_auctions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
  v_count integer := 0;
  v_ended record;
BEGIN
  -- Settle active auctions past ends_at
  FOR v_row IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'active'::auction_status_enum
      AND a.ends_at <= now()
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    IF public.settle_one_auction(v_row.auction_id, false) THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  -- Ensure any ended auction with a winner has an active pending order
  -- UNLESS the winner's order was already cancelled (payment expired).
  FOR v_ended IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
      -- Exclude auctions where a cancelled order exists for the winner
      -- (payment already expired — seller must offer to next bidder or relist)
      AND NOT EXISTS (
        SELECT 1 FROM public.orders oc
        WHERE oc.auction_id = a.auction_id
          AND oc.buyer_id = a.winner_id
          AND oc.order_status = 'cancelled'::order_status_enum
      )
      -- Only if there's no valid pending/paid order
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.auction_id = a.auction_id
          AND o.buyer_id = a.winner_id
          AND (
            (o.order_status = 'pending'::order_status_enum AND o.payment_due_at > now())
            OR EXISTS (
              SELECT 1 FROM public.payments p
              WHERE p.order_id = o.order_id
                AND p.payment_status = 'paid'::payment_status_enum
            )
          )
      )
  LOOP
    PERFORM public.ensure_auction_order(v_ended.auction_id);
  END LOOP;

  PERFORM public.expire_auction_payment_offers();
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.close_auctions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_auctions() TO authenticated, service_role, postgres;

-- ===========================================================================
-- 3. relist_unsold_auction: add optional starting_price / minimum_increment
-- ===========================================================================

-- Drop old 2-param overload so we can create the 4-param version
DROP FUNCTION IF EXISTS public.relist_unsold_auction(uuid, integer);

CREATE OR REPLACE FUNCTION public.relist_unsold_auction(
  p_product_id uuid,
  p_duration_days integer DEFAULT NULL,
  p_starting_price numeric DEFAULT NULL,
  p_minimum_increment numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_auction public.auctions%ROWTYPE;
  v_days integer;
  v_open_offer boolean;
  v_new_start numeric;
  v_new_incr numeric;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_auction
  FROM public.auctions a
  WHERE a.product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.products p
    WHERE p.product_id = p_product_id
      AND p.seller_id = v_uid
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the seller can relist this auction.');
  END IF;

  IF v_auction.status IS DISTINCT FROM 'ended'::auction_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an ended auction can be relisted.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.payments pay ON pay.order_id = o.order_id
    WHERE o.auction_id = v_auction.auction_id
      AND pay.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction was already paid.');
  END IF;

  -- Ensure expired orders are cancelled
  PERFORM public.expire_auction_payment_offers();

  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.auction_id = v_auction.auction_id
      AND o.order_status = 'pending'::order_status_enum
      AND (o.payment_due_at IS NULL OR o.payment_due_at > now())
  ) INTO v_open_offer;

  IF v_open_offer THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A winner still has time to pay.'
    );
  END IF;

  -- Cancel any remaining pending orders for this auction
  UPDATE public.orders
  SET order_status = 'cancelled'::order_status_enum,
      updated_at = now()
  WHERE auction_id = v_auction.auction_id
    AND order_status = 'pending'::order_status_enum;

  v_days := COALESCE(p_duration_days, v_auction.duration_days, 3);
  IF v_days NOT IN (1, 3, 5, 7) THEN
    v_days := 3;
  END IF;

  -- Use new starting price if provided (must be > 0), else keep existing
  v_new_start := COALESCE(NULLIF(p_starting_price, 0), v_auction.starting_price);
  IF v_new_start IS NULL OR v_new_start <= 0 THEN
    v_new_start := v_auction.starting_price;
  END IF;

  -- Use new minimum increment if provided (must be > 0), else keep existing
  v_new_incr := COALESCE(NULLIF(p_minimum_increment, 0), v_auction.minimum_increment);
  IF v_new_incr IS NULL OR v_new_incr <= 0 THEN
    v_new_incr := v_auction.minimum_increment;
  END IF;

  UPDATE public.bids
  SET is_highest_bid = false
  WHERE auction_id = v_auction.auction_id;

  UPDATE public.auctions
  SET bid_round = bid_round + 1,
      status = 'active'::auction_status_enum,
      winner_id = NULL,
      winning_bid_id = NULL,
      starting_price = v_new_start,
      current_price = v_new_start,
      minimum_increment = v_new_incr,
      bid_count = 0,
      duration_days = v_days,
      starts_at = now(),
      ends_at = now() + make_interval(days => v_days),
      updated_at = now()
  WHERE auction_id = v_auction.auction_id;

  -- Also update the product price to match the new starting price
  UPDATE public.products
  SET price = v_new_start,
      status = 'active'::product_status_enum,
      updated_at = now()
  WHERE product_id = p_product_id;

  PERFORM public.release_auction_unit(p_product_id);

  RETURN jsonb_build_object(
    'success', true,
    'auction_id', v_auction.auction_id,
    'starting_price', v_new_start,
    'minimum_increment', v_new_incr,
    'ends_at', now() + make_interval(days => v_days)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.relist_unsold_auction(uuid, integer, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relist_unsold_auction(uuid, integer, numeric, numeric)
  TO authenticated, postgres, service_role;
