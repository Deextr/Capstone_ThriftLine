-- Auction payment window.
--
-- A winner is not a sale. The product stays unsold until PayMongo marks the
-- auction order paid. The winner has 12 hours. If they do not pay, the same
-- order is offered once to the second-highest bidder. If that offer also
-- expires, the auction ends unsold.
--
-- One order per auction (orders.auction_id stays unique). Fallback updates
-- that row. It does not insert another order.
--
-- Idempotent. Do not edit earlier migrations.

-- ===========================================================================
-- 1. Columns
-- ===========================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS auction_offer_rank integer,
  ADD COLUMN IF NOT EXISTS passed_bidder_id uuid,
  ADD COLUMN IF NOT EXISTS auction_offer_started_at timestamptz;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_auction_offer_rank_chk;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_auction_offer_rank_chk
  CHECK (auction_offer_rank IS NULL OR auction_offer_rank IN (1, 2));

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS bid_round integer NOT NULL DEFAULT 1;

ALTER TABLE public.bids
  ADD COLUMN IF NOT EXISTS bid_round integer NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS bids_auction_round_idx
  ON public.bids (auction_id, bid_round, bid_amount DESC);

-- ===========================================================================
-- 2. Stock helpers — reserve without marking sold
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reserve_auction_unit(p_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.products
  SET quantity_available = 0,
      status = CASE
        WHEN status = 'sold'::product_status_enum THEN 'active'::product_status_enum
        ELSE status
      END,
      sold_at = CASE
        WHEN status = 'sold'::product_status_enum THEN NULL
        ELSE sold_at
      END
  WHERE product_id = p_product_id
    AND status IN (
      'active'::product_status_enum,
      'sold'::product_status_enum
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_auction_unit(p_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.products
  SET quantity_available = 1,
      status = 'active'::product_status_enum,
      sold_at = NULL
  WHERE product_id = p_product_id
    AND status IN (
      'active'::product_status_enum,
      'sold'::product_status_enum
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_auction_product_sold(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_product_id uuid;
BEGIN
  SELECT oi.product_id INTO v_product_id
  FROM public.order_items oi
  JOIN public.orders o ON o.order_id = oi.order_id
  WHERE oi.order_id = p_order_id
    AND o.auction_id IS NOT NULL
    AND o.order_status = 'paid'::order_status_enum
  LIMIT 1;

  IF v_product_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.products
  SET status = 'sold'::product_status_enum,
      quantity_available = 0,
      sold_at = COALESCE(sold_at, now())
  WHERE product_id = v_product_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_orders_mark_auction_sold()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.auction_id IS NOT NULL
     AND NEW.order_status = 'paid'::order_status_enum
     AND OLD.order_status IS DISTINCT FROM 'paid'::order_status_enum THEN
    PERFORM public.mark_auction_product_sold(NEW.order_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_mark_auction_sold ON public.orders;
CREATE TRIGGER trg_orders_mark_auction_sold
AFTER UPDATE OF order_status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_mark_auction_sold();

-- ===========================================================================
-- 3. Auction order pricing and winner order
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.auction_checkout_total(p_price numeric)
RETURNS TABLE (
  subtotal numeric,
  shipping_fee numeric,
  platform_fee numeric,
  total_amount numeric
)
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    round(GREATEST(COALESCE(p_price, 0), 0), 2),
    80::numeric,
    round(GREATEST(COALESCE(p_price, 0), 0) * 0.02, 2),
    round(GREATEST(COALESCE(p_price, 0), 0), 2)
      + 80
      + round(GREATEST(COALESCE(p_price, 0), 0) * 0.02, 2);
$$;

CREATE OR REPLACE FUNCTION public.ensure_auction_order(p_auction_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auction record;
  v_product record;
  v_existing uuid;
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

  SELECT o.order_id INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
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

  SELECT o.order_id INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
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

  PERFORM public.notify_user(
    v_auction.winner_id,
    'wonBid',
    'You won the auction',
    'You won the auction for ' || v_name ||
      '. Complete your payment within 12 hours to secure the item.',
    jsonb_build_object(
      'order_id', v_order_id,
      'auction_id', p_auction_id,
      'payment_due_at', now() + interval '12 hours'
    )
  );
  PERFORM public.notify_user(
    v_product.seller_id,
    'system',
    'Awaiting payment',
    v_name || ' has a winner. The listing is not sold until they pay.',
    jsonb_build_object('order_id', v_order_id, 'auction_id', p_auction_id)
  );

  RETURN v_order_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT o.order_id INTO v_order_id
    FROM public.orders o
    WHERE o.auction_id = p_auction_id;
    RETURN v_order_id;
END;
$$;

-- ===========================================================================
-- 4. Settle one auction, then close due windows
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
    PERFORM public.notify_auction_event_once(
      v_auction.seller_id,
      'system',
      'Your auction ended',
      COALESCE(v_auction.product_name, 'Your listing') || ' ended with no bids.',
      p_auction_id,
      'seller_ended_no_bids',
      jsonb_build_object('product_id', v_auction.product_id)
    );
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public._close_unsold_auction_offer(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_product_id uuid;
  v_name text;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum THEN
    RETURN;
  END IF;

  UPDATE public.orders
  SET order_status = 'cancelled'::order_status_enum,
      payment_due_at = now()
  WHERE order_id = p_order_id
    AND order_status = 'pending'::order_status_enum;

  UPDATE public.payments
  SET payment_status = 'failed'::payment_status_enum
  WHERE order_id = p_order_id
    AND payment_status = 'pending'::payment_status_enum;

  SELECT oi.product_id, oi.title
  INTO v_product_id, v_name
  FROM public.order_items oi
  WHERE oi.order_id = p_order_id
  LIMIT 1;

  IF v_product_id IS NOT NULL THEN
    PERFORM public.release_auction_unit(v_product_id);
  END IF;

  UPDATE public.auctions
  SET winner_id = NULL,
      winning_bid_id = NULL,
      updated_at = now()
  WHERE auction_id = v_order.auction_id
    AND status = 'ended'::auction_status_enum;

  PERFORM public.notify_user(
    v_order.buyer_id,
    'system',
    'Payment window ended',
    'The payment window for ' || COALESCE(v_name, 'this auction') ||
      ' has ended. The item was not purchased.',
    jsonb_build_object('order_id', p_order_id, 'auction_id', v_order.auction_id)
  );
  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Auction ended without a sale',
    COALESCE(v_name, 'Your listing') ||
      ' was not paid for. It is now inactive and can be relisted.',
    jsonb_build_object('order_id', p_order_id, 'auction_id', v_order.auction_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_auction_payment_offers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
  v_order public.orders%ROWTYPE;
  v_auction public.auctions%ROWTYPE;
  v_next_bid uuid;
  v_next_bidder uuid;
  v_next_amount numeric;
  v_price numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
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

    SELECT * INTO v_auction
    FROM public.auctions
    WHERE auction_id = v_order.auction_id
    FOR UPDATE;

    SELECT oi.title INTO v_name
    FROM public.order_items oi
    WHERE oi.order_id = v_order.order_id
    LIMIT 1;

    v_next_bid := NULL;
    v_next_bidder := NULL;
    v_next_amount := NULL;
    IF COALESCE(v_order.auction_offer_rank, 1) < 2 THEN
      SELECT b.bid_id, b.bidder_id, b.bid_amount
      INTO v_next_bid, v_next_bidder, v_next_amount
      FROM public.bids b
      WHERE b.auction_id = v_order.auction_id
        AND b.bid_round = COALESCE(v_auction.bid_round, 1)
        AND b.bidder_id IS DISTINCT FROM v_order.buyer_id
      ORDER BY b.bid_amount DESC, b.created_at ASC
      LIMIT 1;
    END IF;

    IF v_next_bidder IS NOT NULL THEN
      SELECT t.subtotal, t.shipping_fee, t.platform_fee, t.total_amount
      INTO v_price, v_shipping, v_platform, v_total
      FROM public.auction_checkout_total(v_next_amount) t;

      UPDATE public.payments
      SET payment_status = 'failed'::payment_status_enum
      WHERE order_id = v_order.order_id
        AND payment_status = 'pending'::payment_status_enum;

      UPDATE public.orders
      SET buyer_id = v_next_bidder,
          subtotal = v_price,
          shipping_fee = v_shipping,
          platform_fee = v_platform,
          total_amount = v_total,
          payment_due_at = now() + interval '12 hours',
          auction_offer_rank = 2,
          passed_bidder_id = v_order.buyer_id,
          auction_offer_started_at = now()
      WHERE order_id = v_order.order_id;

      UPDATE public.order_items
      SET unit_price = v_price,
          line_total = v_price
      WHERE order_id = v_order.order_id;

      UPDATE public.auctions
      SET winner_id = v_next_bidder,
          winning_bid_id = v_next_bid,
          current_price = v_next_amount,
          updated_at = now()
      WHERE auction_id = v_order.auction_id;

      PERFORM public.notify_user(
        v_order.buyer_id,
        'system',
        'Payment window ended',
        'You did not pay for ' || COALESCE(v_name, 'this auction') ||
          ' within 12 hours. The purchase was offered to the next bidder.',
        jsonb_build_object(
          'order_id', v_order.order_id,
          'auction_id', v_order.auction_id,
          'event', 'auction_offer_passed'
        )
      );
      PERFORM public.notify_auction_event_once(
        v_next_bidder,
        'wonBid',
        'You can buy this auction',
        'The original winner did not pay for ' || COALESCE(v_name, 'this item') ||
          '. You can buy it for your bid of ₱' ||
          to_char(v_next_amount, 'FM999999990.00') ||
          '. Complete payment within 12 hours.',
        v_order.auction_id,
        'fallback_offer',
        jsonb_build_object(
          'order_id', v_order.order_id,
          'amount', v_next_amount
        )
      );
    ELSE
      PERFORM public._close_unsold_auction_offer(v_order.order_id);
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

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

  FOR v_ended IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o WHERE o.auction_id = a.auction_id
      )
  LOOP
    PERFORM public.ensure_auction_order(v_ended.auction_id);
  END LOOP;

  PERFORM public.expire_auction_payment_offers();
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_auction_early(p_auction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_auction record;
  v_bids integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT a.auction_id, a.status, a.ends_at, a.current_price, a.bid_round,
         p.seller_id
  INTO v_auction
  FROM public.auctions a
  JOIN public.products p ON p.product_id = a.product_id
  WHERE a.auction_id = p_auction_id;

  IF NOT FOUND OR v_auction.seller_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  IF v_auction.status IS DISTINCT FROM 'active'::auction_status_enum
     OR v_auction.ends_at <= now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction has already ended.');
  END IF;

  SELECT count(*)::integer INTO v_bids
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round;

  IF v_bids < 1 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'End the auction early only after someone has bid.'
    );
  END IF;

  IF NOT public.settle_one_auction(p_auction_id, true) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not end this auction.');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'auction_id', p_auction_id,
    'current_price', v_auction.current_price
  );
END;
$$;

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
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
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

-- ===========================================================================
-- 5. place_bid records the current round
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

  v_min_bid := COALESCE(v_auction.current_price, v_auction.starting_price, 0)
    + COALESCE(v_auction.minimum_increment, 0);

  IF COALESCE(v_auction.minimum_increment, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction has an invalid bid increment.');
  END IF;

  IF p_amount < v_min_bid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Bid must be at least ' || v_min_bid::text);
  END IF;

  SELECT b.bidder_id INTO v_prev_bidder
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
    AND b.is_highest_bid = true
  LIMIT 1;

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

-- Current-round bids only, so a relisted auction does not revive old winners.
DROP VIEW IF EXISTS public.v_user_bids;
CREATE VIEW public.v_user_bids
WITH (security_invoker = true) AS
SELECT
  b.bid_id,
  b.auction_id,
  b.bidder_id,
  b.bid_amount,
  b.is_highest_bid,
  b.created_at,
  a.product_id,
  a.starting_price,
  a.minimum_increment,
  a.current_price,
  a.winner_id,
  a.starts_at,
  a.ends_at,
  a.status AS auction_status,
  o.payment_due_at,
  o.order_status AS auction_order_status,
  CASE
    WHEN a.status IN ('ended'::auction_status_enum, 'cancelled'::auction_status_enum)
         AND a.winner_id IS NOT NULL
         AND a.winner_id IS NOT DISTINCT FROM b.bidder_id THEN 'won'
    WHEN a.status IN ('ended'::auction_status_enum, 'cancelled'::auction_status_enum) THEN 'lost'
    WHEN a.status = 'active'::auction_status_enum AND a.ends_at <= now()
         AND COALESCE(a.winner_id, (
           SELECT hb.bidder_id
           FROM public.bids hb
           WHERE hb.auction_id = a.auction_id
             AND hb.bid_round = a.bid_round
           ORDER BY hb.bid_amount DESC, hb.created_at ASC
           LIMIT 1
         )) IS NOT DISTINCT FROM b.bidder_id THEN 'won'
    WHEN a.status = 'active'::auction_status_enum AND a.ends_at <= now() THEN 'lost'
    WHEN b.is_highest_bid THEN 'winning'
    ELSE 'outbid'
  END AS bid_status
FROM (
  SELECT DISTINCT ON (bidder_id, auction_id)
    bid_id, auction_id, bidder_id, bid_amount, is_highest_bid, bid_round, created_at
  FROM public.bids
  ORDER BY bidder_id, auction_id, bid_round DESC, bid_amount DESC, created_at DESC
) b
JOIN public.auctions a ON a.auction_id = b.auction_id
LEFT JOIN public.orders o ON o.auction_id = a.auction_id
WHERE b.bid_round = a.bid_round
  AND (b.bidder_id = auth.uid() OR public.is_admin());

GRANT SELECT ON public.v_user_bids TO authenticated;

-- ===========================================================================
-- 6. PayMongo: reject a closed or moved auction offer
-- ===========================================================================

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
  PERFORM public.expire_auction_payment_offers();

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

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    IF v_order.passed_bidder_id IS NOT DISTINCT FROM v_buyer
       OR v_order.auction_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Your payment window for this auction has ended.'
      );
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.auction_id IS NOT NULL
     AND v_order.payment_due_at IS NOT NULL
     AND v_order.payment_due_at <= now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your payment window for this auction has ended.'
    );
  END IF;

  IF v_order.order_status = 'cancelled'::order_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',
      CASE
        WHEN v_order.auction_id IS NOT NULL
          THEN 'Your payment window for this auction has ended.'
        ELSE 'This checkout was not completed. The item is back in your cart.'
      END
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
       AND v_payment.updated_at > now() - interval '15 minutes'
       AND (
         v_order.auction_offer_started_at IS NULL
         OR v_payment.created_at >= v_order.auction_offer_started_at
       ) THEN
      v_reuse := true;
    END IF;
  ELSE
    INSERT INTO public.payments (
      order_id, payment_method, total_amount, payment_status,
      amount_centavos, currency, paymongo_channel
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
  v_stale_auction boolean := false;
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

  v_paid := p_event_type IN ('checkout_session.payment.paid', 'payment.paid');
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

  PERFORM public.expire_auction_payment_offers();

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

  IF v_paid AND v_order.auction_id IS NOT NULL THEN
    v_stale_auction :=
      v_order.order_status = 'cancelled'::order_status_enum
      OR (
        v_order.payment_due_at IS NOT NULL
        AND v_order.payment_due_at <= now()
      )
      OR (
        v_order.auction_offer_started_at IS NOT NULL
        AND v_payment.created_at < v_order.auction_offer_started_at
      )
      OR v_payment.payment_status = 'failed'::payment_status_enum;
  END IF;

  IF v_stale_auction THEN
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
      'auction_window_closed', true,
      'payment_id', v_payment.payment_id,
      'order_id', v_order.order_id
    );
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
        p_event_key, COALESCE(p_event_type, 'unknown'),
        v_payment.payment_id, v_order.order_id
      )
      ON CONFLICT (event_key) DO NOTHING;
      RETURN jsonb_build_object(
        'success', true, 'ignored', true, 'already_voided', true,
        'payment_id', v_payment.payment_id, 'order_id', v_order.order_id
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
    IF v_order.auction_id IS NULL THEN
      v_void := public.void_unpaid_checkout(v_order.order_id);
    END IF;
  END IF;

  INSERT INTO public.paymongo_webhook_events (
    event_key, event_type, payment_id, order_id
  )
  VALUES (
    p_event_key, COALESCE(p_event_type, 'unknown'),
    v_payment.payment_id, v_order.order_id
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

-- Existing unpaid auction orders get a fresh 12-hour window and are not Sold.
UPDATE public.orders o
SET payment_due_at = now() + interval '12 hours',
    auction_offer_rank = COALESCE(o.auction_offer_rank, 1),
    auction_offer_started_at = COALESCE(o.auction_offer_started_at, o.created_at)
WHERE o.auction_id IS NOT NULL
  AND o.order_status = 'pending'::order_status_enum
  AND o.payment_due_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::payment_status_enum
  );

UPDATE public.products p
SET status = 'active'::product_status_enum,
    sold_at = NULL,
    quantity_available = 0
FROM public.order_items oi
JOIN public.orders o ON o.order_id = oi.order_id
WHERE oi.product_id = p.product_id
  AND o.auction_id IS NOT NULL
  AND o.order_status = 'pending'::order_status_enum
  AND p.status = 'sold'::product_status_enum
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments pay
    WHERE pay.order_id = o.order_id
      AND pay.payment_status = 'paid'::payment_status_enum
  );

CREATE OR REPLACE FUNCTION public.sync_my_unpaid_checkouts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM public.expire_unpaid_checkouts();
  PERFORM public.expire_auction_payment_offers();
  PERFORM public.close_auctions();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_my_unpaid_checkouts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_my_unpaid_checkouts()
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 7. Grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.reserve_auction_unit(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_auction_unit(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.release_auction_unit(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_auction_unit(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.mark_auction_product_sold(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_auction_product_sold(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.auction_checkout_total(numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auction_checkout_total(numeric) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.ensure_auction_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_auction_order(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.settle_one_auction(uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_one_auction(uuid, boolean) TO postgres, service_role;

REVOKE ALL ON FUNCTION public._close_unsold_auction_offer(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._close_unsold_auction_offer(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.expire_auction_payment_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_auction_payment_offers()
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.close_auctions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_auctions()
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.end_auction_early(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_auction_early(uuid)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.relist_unsold_auction(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relist_unsold_auction(uuid, integer)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.prepare_paymongo_checkout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_paymongo_checkout(uuid, text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.apply_paymongo_event(text, text, text, text, integer, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paymongo_event(text, text, text, text, integer, text, uuid)
  TO postgres, service_role;
