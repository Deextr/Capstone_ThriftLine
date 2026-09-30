-- Migration: 20260929200000_auction_bidding_and_fallback_offer.sql
-- Description:
-- 1. Seller sets the product as an auction (starting bid, minimum increment, duration).
-- 2. Buyer bid must be >= current highest bid + minimum increment (or starting price + min increment).
-- 3. Bids cannot be retracted (public.bids has SELECT-only RLS for users).
-- 4. When auction ends:
--    - Highest valid bid becomes the winning bid.
--    - System records winner and final bid amount.
--    - Winner receives an order with a 12-hour payment deadline.
--    - If nobody bids before end time: auction ends with NO WINNER (no order created, seller can relist).
-- 5. Winner fails to pay:
--    - Order expires/cancels after payment deadline (12 hours).
--    - Seller can offer the item to the next-highest valid bidder via offer_auction_to_next_bidder.
--    - Or seller can relist the item via relist_unsold_auction.
-- 6. Sellers cannot bid on their own listings.

-- ===========================================================================
-- 1. place_bid: enforces minimum increment, seller-check, and active status
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.place_bid(
  p_auction_id uuid,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auction record;
  v_bid_id uuid;
  v_user_id uuid;
  v_min_bid numeric;
  v_prev_bidder uuid;
  v_count integer;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required to place a bid.');
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid bid amount.');
  END IF;

  SELECT a.auction_id, a.product_id, a.starting_price, a.minimum_increment,
         a.current_price, a.winner_id, a.starts_at, a.ends_at, a.status,
         a.bid_round, p.seller_id, p.name AS product_name
  INTO v_auction
  FROM public.auctions a
  JOIN public.products p ON p.product_id = a.product_id
  WHERE a.auction_id = p_auction_id
  FOR UPDATE OF a;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  -- Sellers cannot bid on their own listings
  IF v_auction.seller_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sellers cannot bid on their own listings.');
  END IF;

  IF v_auction.status = 'cancelled'::auction_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction was cancelled.');
  END IF;

  IF v_auction.status <> 'active'::auction_status_enum
     OR v_auction.ends_at <= now() THEN
    PERFORM public.close_auctions();
    RETURN jsonb_build_object('success', false, 'error', 'This auction has already ended.');
  END IF;

  IF v_auction.starts_at > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction has not started yet.');
  END IF;

  -- Minimum valid bid: current highest bid + minimum increment
  v_min_bid := COALESCE(v_auction.current_price, v_auction.starting_price, 0)
    + COALESCE(v_auction.minimum_increment, 0);

  IF COALESCE(v_auction.minimum_increment, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction has an invalid bid increment.');
  END IF;

  IF p_amount < v_min_bid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Bid must be at least ₱' || to_char(v_min_bid, 'FM999999990.00'));
  END IF;

  SELECT b.bidder_id INTO v_prev_bidder
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
    AND b.is_highest_bid = true
  LIMIT 1;

  -- Bids cannot be retracted; mark previous highest bid as superseded
  UPDATE public.bids
  SET is_highest_bid = false, updated_at = now()
  WHERE auction_id = p_auction_id
    AND bid_round = v_auction.bid_round
    AND is_highest_bid = true;

  INSERT INTO public.bids (
    auction_id, bidder_id, bid_amount, is_highest_bid, bid_round, created_at, updated_at
  )
  VALUES (
    p_auction_id, v_user_id, p_amount, true, v_auction.bid_round, now(), now()
  )
  RETURNING bid_id INTO v_bid_id;

  SELECT count(*)::integer INTO v_count
  FROM public.bids
  WHERE auction_id = p_auction_id
    AND bid_round = v_auction.bid_round;

  UPDATE public.auctions
  SET current_price = p_amount,
      winner_id = v_user_id,
      winning_bid_id = v_bid_id,
      bid_count = v_count,
      updated_at = now()
  WHERE auction_id = p_auction_id;

  IF v_prev_bidder IS NOT NULL AND v_prev_bidder IS DISTINCT FROM v_user_id THEN
    PERFORM public.notify_user(
      v_prev_bidder,
      'outbid',
      'You''ve been outbid',
      'Someone bid ₱' || to_char(p_amount, 'FM999999990.00') ||
        ' on ' || COALESCE(v_auction.product_name, 'an auction') || '.',
      jsonb_build_object(
        'auction_id', p_auction_id,
        'product_id', v_auction.product_id,
        'bid_id', v_bid_id,
        'amount', p_amount,
        'event', 'outbid'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'bid_id', v_bid_id,
    'auction_id', p_auction_id,
    'current_price', p_amount,
    'min_next_bid', p_amount + COALESCE(v_auction.minimum_increment, 0),
    'message', 'Bid placed successfully!'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric)
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 2. settle_one_auction: records winner or ends with no winner
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.settle_one_auction(
  p_auction_id uuid,
  p_force boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auction record;
  v_win record;
  v_updated integer;
BEGIN
  SELECT a.auction_id, a.product_id, a.status, a.ends_at, a.bid_round,
         a.current_price, p.seller_id, p.name AS product_name
  INTO v_auction
  FROM public.auctions a
  JOIN public.products p ON p.product_id = a.product_id
  WHERE a.auction_id = p_auction_id
  FOR UPDATE OF a;

  IF NOT FOUND OR v_auction.status IS DISTINCT FROM 'active'::auction_status_enum THEN
    RETURN false;
  END IF;

  IF NOT COALESCE(p_force, false) AND v_auction.ends_at > now() THEN
    RETURN false;
  END IF;

  -- Find highest valid bid in current round
  SELECT b.bid_id, b.bidder_id, b.bid_amount
  INTO v_win
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
  ORDER BY b.bid_amount DESC, b.created_at ASC
  LIMIT 1;

  IF COALESCE(p_force, false) AND v_win.bidder_id IS NULL THEN
    RETURN false;
  END IF;

  -- Record the winner and final bid amount, or NULL if no bids
  UPDATE public.auctions
  SET status = 'ended'::auction_status_enum,
      ends_at = CASE WHEN COALESCE(p_force, false) THEN now() ELSE ends_at END,
      winner_id = v_win.bidder_id,
      winning_bid_id = v_win.bid_id,
      current_price = COALESCE(v_win.bid_amount, current_price),
      bid_count = (
        SELECT count(*)::integer
        FROM public.bids
        WHERE auction_id = p_auction_id
          AND bid_round = v_auction.bid_round
      ),
      updated_at = now()
  WHERE auction_id = p_auction_id
    AND status = 'active'::auction_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN false;
  END IF;

  IF v_win.bidder_id IS NOT NULL THEN
    -- Winner must proceed to checkout: receives an order with 12-hour deadline
    PERFORM public.notify_auction_event_once(
      v_win.bidder_id,
      'wonBid',
      'You won the auction',
      'You won the auction for ' || COALESCE(v_auction.product_name, 'this item') ||
        '. Complete your payment within 12 hours to secure the item.',
      p_auction_id,
      'won',
      jsonb_build_object(
        'product_id', v_auction.product_id,
        'bid_id', v_win.bid_id,
        'amount', v_win.bid_amount
      )
    );
    PERFORM public.ensure_auction_order(p_auction_id);
  ELSIF v_auction.seller_id IS NOT NULL THEN
    -- If nobody bids before the end time, listing becomes Auction Ended — No Winner
    PERFORM public.notify_auction_event_once(
      v_auction.seller_id,
      'system',
      'Auction Ended — No Winner',
      COALESCE(v_auction.product_name, 'Your listing') || ' ended with no bids. You can relist the item.',
      p_auction_id,
      'seller_ended_no_bids',
      jsonb_build_object('product_id', v_auction.product_id)
    );
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.settle_one_auction(uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_one_auction(uuid, boolean) TO postgres, service_role;

-- ===========================================================================
-- 3. expire_auction_payment_offers: cancels order when 12-hour deadline expires
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.expire_auction_payment_offers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
  v_order public.orders%ROWTYPE;
  v_product_id uuid;
  v_name text;
  v_count integer := 0;
BEGIN
  FOR r IN
    SELECT o.order_id
    FROM public.orders o
    WHERE o.auction_id IS NOT NULL
      AND o.order_status = 'pending'::order_status_enum
      AND o.payment_due_at IS NOT NULL
      AND o.payment_due_at <= now()
      AND NOT EXISTS (
        SELECT 1
        FROM public.payments p
        WHERE p.order_id = o.order_id
          AND p.payment_status = 'paid'::payment_status_enum
      )
    FOR UPDATE OF o SKIP LOCKED
  LOOP
    SELECT * INTO v_order
    FROM public.orders
    WHERE order_id = r.order_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum
       OR v_order.payment_due_at > now() THEN
      CONTINUE;
    END IF;

    SELECT oi.product_id, oi.title
    INTO v_product_id, v_name
    FROM public.order_items oi
    WHERE oi.order_id = v_order.order_id
    LIMIT 1;

    -- Cancel the unpaid expired order
    UPDATE public.orders
    SET order_status = 'cancelled'::order_status_enum,
        updated_at = now()
    WHERE order_id = v_order.order_id;

    UPDATE public.payments
    SET payment_status = 'failed'::payment_status_enum,
        updated_at = now()
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::payment_status_enum;

    -- Notify the buyer who failed to pay
    PERFORM public.notify_user(
      v_order.buyer_id,
      'system',
      'Payment deadline expired',
      'The 12-hour payment deadline for ' || COALESCE(v_name, 'this auction') ||
        ' has expired. The order has been cancelled.',
      jsonb_build_object('order_id', v_order.order_id, 'auction_id', v_order.auction_id)
    );

    -- Notify the seller that buyer failed to pay, and seller can relist or offer to next bidder
    PERFORM public.notify_user(
      v_order.seller_id,
      'system',
      'Buyer failed to pay',
      'The winner for ' || COALESCE(v_name, 'your auction') ||
        ' did not complete payment within 12 hours. You can offer the item to the next highest bidder or relist it.',
      jsonb_build_object(
        'order_id', v_order.order_id,
        'auction_id', v_order.auction_id,
        'event', 'auction_payment_expired'
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_auction_payment_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_auction_payment_offers()
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 4. offer_auction_to_next_bidder: seller offers item to 2nd highest bidder
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.offer_auction_to_next_bidder(p_auction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_auction public.auctions%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_next_bid uuid;
  v_next_bidder uuid;
  v_next_amount numeric;
  v_price numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_name text;
  v_prev_winner uuid;
  v_address_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_image text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_auction_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction ID is required.');
  END IF;

  SELECT * INTO v_auction
  FROM public.auctions
  WHERE auction_id = p_auction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  SELECT * INTO v_product
  FROM public.products
  WHERE product_id = v_auction.product_id;

  IF v_product.seller_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the seller can offer this auction to the next bidder.');
  END IF;

  IF v_auction.status IS DISTINCT FROM 'ended'::auction_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an ended auction can be offered to the next bidder.');
  END IF;

  -- Check if paid
  IF EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.payments p ON p.order_id = o.order_id
    WHERE o.auction_id = p_auction_id AND p.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction was already paid.');
  END IF;

  -- Ensure expired orders are processed
  PERFORM public.expire_auction_payment_offers();

  SELECT * INTO v_order
  FROM public.orders
  WHERE auction_id = p_auction_id
  FOR UPDATE;

  -- Check if the current order is still within its open payment window
  IF v_order.order_id IS NOT NULL
     AND v_order.order_status = 'pending'::order_status_enum
     AND v_order.payment_due_at > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'The current winner still has time to pay.');
  END IF;

  -- Find the previous buyer to exclude
  v_prev_winner := COALESCE(v_order.passed_bidder_id, v_order.buyer_id, v_auction.winner_id);

  -- Find the next-highest valid bidder from current round
  SELECT b.bid_id, b.bidder_id, b.bid_amount
  INTO v_next_bid, v_next_bidder, v_next_amount
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
    AND b.bidder_id IS DISTINCT FROM v_prev_winner
    AND b.bidder_id IS DISTINCT FROM v_uid
  ORDER BY b.bid_amount DESC, b.created_at ASC
  LIMIT 1;

  IF v_next_bidder IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No other valid bidders found for this auction. You can relist the item.');
  END IF;

  SELECT t.subtotal, t.shipping_fee, t.platform_fee, t.total_amount
  INTO v_price, v_shipping, v_platform, v_total
  FROM public.auction_checkout_total(v_next_amount) t;

  v_name := COALESCE(NULLIF(btrim(v_product.name), ''), 'this item');

  SELECT a.address_id INTO v_address_id
  FROM public.addresses a
  WHERE a.user_id = v_next_bidder
  ORDER BY a.is_default DESC, a.created_at DESC
  LIMIT 1;

  IF v_address_id IS NOT NULL THEN
    v_snapshot := public.order_address_snapshot(v_address_id);
  END IF;

  -- Update or insert order for the next bidder
  IF v_order.order_id IS NOT NULL THEN
    UPDATE public.payments
    SET payment_status = 'failed'::payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::payment_status_enum;

    UPDATE public.orders
    SET buyer_id = v_next_bidder,
        order_status = 'pending'::order_status_enum,
        subtotal = v_price,
        shipping_fee = v_shipping,
        platform_fee = v_platform,
        total_amount = v_total,
        shipping_address = v_snapshot,
        payment_due_at = now() + interval '12 hours',
        auction_offer_rank = 2,
        passed_bidder_id = v_prev_winner,
        auction_offer_started_at = now(),
        updated_at = now()
    WHERE order_id = v_order.order_id;

    UPDATE public.order_items
    SET unit_price = v_price,
        line_total = v_price
    WHERE order_id = v_order.order_id;
  ELSE
    SELECT pi.image_url INTO v_image
    FROM public.product_images pi
    WHERE pi.product_id = v_product.product_id
    ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
    LIMIT 1;

    INSERT INTO public.orders (
      order_number, buyer_id, seller_id, auction_id, order_type, order_status,
      subtotal, shipping_fee, platform_fee, total_amount, shipping_address,
      payment_due_at, auction_offer_rank, auction_offer_started_at
    )
    VALUES (
      public.next_order_number(),
      v_next_bidder,
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
      2,
      now()
    )
    RETURNING order_id INTO v_order.order_id;

    INSERT INTO public.order_items (
      order_id, product_id, auction_id, title, image_url, size,
      unit_price, quantity, line_total
    )
    VALUES (
      v_order.order_id, v_product.product_id, p_auction_id, v_name, v_image,
      v_product.size, v_price, 1, v_price
    );
  END IF;

  PERFORM public.reserve_auction_unit(v_product.product_id);

  UPDATE public.auctions
  SET winner_id = v_next_bidder,
      winning_bid_id = v_next_bid,
      current_price = v_next_amount,
      updated_at = now()
  WHERE auction_id = p_auction_id;

  -- Notify next bidder
  PERFORM public.notify_auction_event_once(
    v_next_bidder,
    'wonBid',
    'You can buy this auction',
    'The seller offered you ' || v_name ||
      ' for your bid of ₱' ||
      to_char(v_next_amount, 'FM999999990.00') ||
      '. Complete payment within 12 hours.',
    p_auction_id,
    'seller_fallback_offer',
    jsonb_build_object(
      'order_id', v_order.order_id,
      'amount', v_next_amount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'auction_id', p_auction_id,
    'order_id', v_order.order_id,
    'next_bidder_id', v_next_bidder,
    'amount', v_next_amount
  );
END;
$$;

REVOKE ALL ON FUNCTION public.offer_auction_to_next_bidder(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offer_auction_to_next_bidder(uuid)
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 5. relist_unsold_auction: cancels expired order & reopens bidding
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.relist_unsold_auction(
  p_product_id uuid,
  p_duration_days integer DEFAULT NULL
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

  UPDATE public.bids
  SET is_highest_bid = false
  WHERE auction_id = v_auction.auction_id;

  UPDATE public.auctions
  SET bid_round = bid_round + 1,
      status = 'active'::auction_status_enum,
      winner_id = NULL,
      winning_bid_id = NULL,
      current_price = starting_price,
      bid_count = 0,
      duration_days = v_days,
      starts_at = now(),
      ends_at = now() + make_interval(days => v_days),
      updated_at = now()
  WHERE auction_id = v_auction.auction_id;

  PERFORM public.release_auction_unit(p_product_id);

  RETURN jsonb_build_object(
    'success', true,
    'auction_id', v_auction.auction_id,
    'ends_at', now() + make_interval(days => v_days)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.relist_unsold_auction(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relist_unsold_auction(uuid, integer)
  TO authenticated, postgres, service_role;
