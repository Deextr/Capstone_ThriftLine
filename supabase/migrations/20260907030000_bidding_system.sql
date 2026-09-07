-- =============================================================================
-- Migration: 20260907030000_bidding_system.sql
-- Description: Adds atomic place_bid RPC function with SECURITY DEFINER,
--              real-time publication updates, and auction winner resolution.
-- =============================================================================

-- Ensure RLS on bids allows inserts from authenticated users for themselves
DROP POLICY IF EXISTS "bids_insert_own" ON public.bids;
CREATE POLICY "bids_insert_own" ON public.bids
  FOR INSERT
  WITH CHECK (auth.uid() = bidder_id);

-- Ensure public can select bids
DROP POLICY IF EXISTS "bids_select_all" ON public.bids;
CREATE POLICY "bids_select_all" ON public.bids
  FOR SELECT
  USING (true);

-- Atomic bid placement function with validation and auto auction price update
CREATE OR REPLACE FUNCTION public.place_bid(
  p_auction_id UUID,
  p_amount NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auction RECORD;
  v_bid_id UUID;
  v_user_id UUID;
  v_seller_id UUID;
  v_min_bid NUMERIC;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Authentication required to place a bid.'
    );
  END IF;

  -- 1. Fetch auction and product details (locking the auction row for concurrency)
  SELECT a.*, p.seller_id
  INTO v_auction
  FROM public.auctions a
  JOIN public.products p ON p.product_id = a.product_id
  WHERE a.auction_id = p_auction_id
  FOR UPDATE OF a;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Auction not found.'
    );
  END IF;

  -- 2. Validate seller cannot bid on own product
  IF v_auction.seller_id = v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Sellers cannot bid on their own listings.'
    );
  END IF;

  -- 3. Validate auction status and end time
  IF v_auction.status != 'active' OR v_auction.ends_at <= now() THEN
    -- If time expired but status was active, mark ended
    IF v_auction.status = 'active' AND v_auction.ends_at <= now() THEN
      UPDATE public.auctions
      SET status = 'ended', updated_at = now()
      WHERE auction_id = p_auction_id;
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'This auction has already ended.'
    );
  END IF;

  -- 4. Validate bid amount >= current_price + minimum_increment
  v_min_bid := COALESCE(v_auction.current_price, v_auction.starting_price, 0) + COALESCE(v_auction.minimum_increment, 20);
  IF p_amount < v_min_bid THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Bid must be at least ' || v_min_bid
    );
  END IF;

  -- 5. Mark previous highest bids for this auction as not highest
  UPDATE public.bids
  SET is_highest_bid = false,
      updated_at = now()
  WHERE auction_id = p_auction_id AND is_highest_bid = true;

  -- 6. Insert new bid
  INSERT INTO public.bids (
    auction_id,
    bidder_id,
    bid_amount,
    is_highest_bid,
    created_at,
    updated_at
  )
  VALUES (
    p_auction_id,
    v_user_id,
    p_amount,
    true,
    now(),
    now()
  )
  RETURNING bid_id INTO v_bid_id;

  -- 7. Update auction price and winner
  UPDATE public.auctions
  SET current_price = p_amount,
      winner_id = v_user_id,
      updated_at = now()
  WHERE auction_id = p_auction_id;

  RETURN jsonb_build_object(
    'success', true,
    'bid_id', v_bid_id,
    'auction_id', p_auction_id,
    'current_price', p_amount,
    'message', 'Bid placed successfully!'
  );
END;
$$;

-- Function to settle / close ended auctions
CREATE OR REPLACE FUNCTION public.settle_ended_auctions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settled_count INTEGER := 0;
BEGIN
  UPDATE public.auctions
  SET status = 'ended',
      updated_at = now()
  WHERE status = 'active' AND ends_at <= now();

  GET DIAGNOSTICS v_settled_count = ROW_COUNT;
  RETURN v_settled_count;
END;
$$;

-- Add bids and auctions to supabase_realtime publication if not already present
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'bids'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bids;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'auctions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.auctions;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    -- Ignore if publication does not exist or user lacks superuser rights
    NULL;
END;
$$;
