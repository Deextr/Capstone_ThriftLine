-- Migration: 20260929220000_fix_payment_due_at_backfill.sql
-- Description:
-- 1. Fix ensure_auction_order so that it refreshes/updates the order when an auction is
--    settled in a new round or after relisting/expiry, giving the winning bidder a fresh
--    12-hour payment window instead of keeping a stale/cancelled order from an earlier round.
-- 2. Fix close_auctions() so that ended auctions with winners guarantee an active pending order.
-- 3. Update v_user_bids view to join orders specifically on auction_id AND buyer_id = bidder_id.
-- 4. Backfill existing ended auctions that have a winner but no active/paid order so they get
--    a fresh 12-hour payment window immediately.

-- ===========================================================================
-- 1. ensure_auction_order: refresh order for current winner with 12h deadline
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

    -- Otherwise, refresh this order for the current winner with a fresh 12-hour window
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
-- 2. close_auctions: ensure active order exists for any ended auction winner
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

  -- Ensure any ended auction with a winner has an active pending order for that winner
  FOR v_ended IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
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
-- 3. v_user_bids view: join orders with buyer_id = bidder_id guard
-- ===========================================================================

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
LEFT JOIN public.orders o ON o.auction_id = a.auction_id AND o.buyer_id = b.bidder_id
WHERE b.bid_round = a.bid_round
  AND (b.bidder_id = auth.uid() OR public.is_admin());

GRANT SELECT ON public.v_user_bids TO authenticated;

-- ===========================================================================
-- 4. Backfill: refresh orders for existing won auctions
-- ===========================================================================

DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.orders o
        JOIN public.payments p ON p.order_id = o.order_id
        WHERE o.auction_id = a.auction_id
          AND p.payment_status = 'paid'::payment_status_enum
      )
  LOOP
    PERFORM public.ensure_auction_order(v_rec.auction_id);
  END LOOP;
END;
$$;
