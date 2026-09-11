-- Phase 3 — Auctions and bidding (corrective).
--
-- Does NOT rewrite 20260907030000_bidding_system.sql or
-- 20260907040000_ensure_auctions.sql. Those stay in history.
-- This file:
--   * keeps auctions/bids column names (bid_amount, ends_at, status=ended)
--   * makes place_bid the only client bid-write path
--   * adds close_auctions() with winner + idempotent notifications
--   * replaces the hardcoded 3-day/₱20 listing trigger with ensure_product_auction
--   * adds v_user_bids for authoritative Leading/Outbid/Won/Lost
--
-- No pending orders (Phase 5). No payments (Phase 6).
-- Idempotent. Safe to re-run.

-- ===========================================================================
-- 1. Schema: one auction per product, optional denormalized fields
-- ===========================================================================

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS duration_days integer,
  ADD COLUMN IF NOT EXISTS bid_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS winning_bid_id uuid;

-- Drop bid-less duplicate auction rows so UNIQUE(product_id) can be added.
DELETE FROM public.auctions a
WHERE NOT EXISTS (SELECT 1 FROM public.bids b WHERE b.auction_id = a.auction_id)
  AND EXISTS (
    SELECT 1
    FROM public.auctions keep
    WHERE keep.product_id = a.product_id
      AND keep.auction_id <> a.auction_id
      AND keep.created_at <= a.created_at
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'auctions_product_id_key'
      AND conrelid = 'public.auctions'::regclass
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'auctions_product_id_key'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.auctions GROUP BY product_id HAVING count(*) > 1
    ) THEN
      ALTER TABLE public.auctions
        ADD CONSTRAINT auctions_product_id_key UNIQUE (product_id);
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'auctions_winning_bid_id_fkey'
  ) THEN
    ALTER TABLE public.auctions
      ADD CONSTRAINT auctions_winning_bid_id_fkey
      FOREIGN KEY (winning_bid_id)
      REFERENCES public.bids (bid_id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS bids_auction_amount_idx
  ON public.bids (auction_id, bid_amount DESC, created_at ASC);

CREATE INDEX IF NOT EXISTS bids_bidder_created_idx
  ON public.bids (bidder_id, created_at DESC);

CREATE INDEX IF NOT EXISTS auctions_active_ends_idx
  ON public.auctions (ends_at)
  WHERE status = 'active';

-- Leftover prototype trigger targeting a table named "bidding".
DROP FUNCTION IF EXISTS public.handle_new_bid() CASCADE;

-- ===========================================================================
-- 2. Drop the hardcoded listing trigger (increment 20, +3 days).
--    Sellers pass real duration/increment through ensure_product_auction.
-- ===========================================================================

DROP TRIGGER IF EXISTS trg_products_auction_sync ON public.products;
DROP FUNCTION IF EXISTS public.handle_product_auction_sync();

-- ===========================================================================
-- 3. Idempotent auction notifications (reuse Phase 1 notify_user)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.notify_auction_event_once(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_auction_id uuid,
  p_event text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
BEGIN
  IF p_user_id IS NULL OR p_auction_id IS NULL THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = p_user_id
      AND n.type = p_type
      AND n.data->>'auction_id' = p_auction_id::text
      AND COALESCE(n.data->>'event', '') = COALESCE(p_event, '')
  ) THEN
    RETURN;
  END IF;

  v_payload := COALESCE(p_data, '{}'::jsonb)
    || jsonb_build_object(
      'auction_id', p_auction_id,
      'event', p_event
    );

  PERFORM public.notify_user(p_user_id, p_type, p_title, p_body, v_payload);
END;
$$;

REVOKE ALL ON FUNCTION public.notify_auction_event_once(uuid, text, text, text, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_auction_event_once(uuid, text, text, text, uuid, text, jsonb)
  TO postgres, service_role;

-- ===========================================================================
-- 4. close_auctions — idempotent settle, no orders
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.close_auctions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
  v_win record;
  v_updated integer;
  v_count integer := 0;
BEGIN
  FOR v_row IN
    SELECT a.auction_id, a.product_id, p.seller_id, p.name AS product_name
    FROM public.auctions a
    JOIN public.products p ON p.product_id = a.product_id
    WHERE a.status = 'active'::auction_status_enum
      AND a.ends_at <= now()
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    SELECT b.bid_id, b.bidder_id, b.bid_amount
    INTO v_win
    FROM public.bids b
    WHERE b.auction_id = v_row.auction_id
    ORDER BY b.bid_amount DESC, b.created_at ASC
    LIMIT 1;

    UPDATE public.auctions
    SET status = 'ended'::auction_status_enum,
        winner_id = v_win.bidder_id,
        winning_bid_id = v_win.bid_id,
        current_price = COALESCE(v_win.bid_amount, current_price),
        bid_count = (SELECT count(*)::integer FROM public.bids WHERE auction_id = v_row.auction_id),
        updated_at = now()
    WHERE auction_id = v_row.auction_id
      AND status = 'active'::auction_status_enum;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
      CONTINUE;
    END IF;

    v_count := v_count + 1;

    IF v_win.bidder_id IS NOT NULL THEN
      PERFORM public.notify_auction_event_once(
        v_win.bidder_id,
        'wonBid',
        'You won the auction',
        'You won ' || COALESCE(v_row.product_name, 'an auction') ||
          ' with a bid of ₱' || to_char(v_win.bid_amount, 'FM999999990.00') || '.',
        v_row.auction_id,
        'won',
        jsonb_build_object(
          'product_id', v_row.product_id,
          'bid_id', v_win.bid_id,
          'amount', v_win.bid_amount
        )
      );
    END IF;

    IF v_row.seller_id IS NOT NULL THEN
      IF v_win.bidder_id IS NOT NULL THEN
        PERFORM public.notify_auction_event_once(
          v_row.seller_id,
          'system',
          'Your auction ended',
          COALESCE(v_row.product_name, 'Your listing') ||
            ' sold via auction for ₱' || to_char(v_win.bid_amount, 'FM999999990.00') || '.',
          v_row.auction_id,
          'seller_ended_winner',
          jsonb_build_object(
            'product_id', v_row.product_id,
            'winner_id', v_win.bidder_id,
            'amount', v_win.bid_amount
          )
        );
      ELSE
        PERFORM public.notify_auction_event_once(
          v_row.seller_id,
          'system',
          'Your auction ended',
          COALESCE(v_row.product_name, 'Your listing') ||
            ' ended with no bids.',
          v_row.auction_id,
          'seller_ended_no_bids',
          jsonb_build_object('product_id', v_row.product_id)
        );
      END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_ended_auctions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.close_auctions();
END;
$$;

REVOKE ALL ON FUNCTION public.close_auctions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_auctions() TO authenticated, service_role, postgres;

REVOKE ALL ON FUNCTION public.settle_ended_auctions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.settle_ended_auctions() TO authenticated, service_role, postgres;

-- ===========================================================================
-- 5. place_bid — lock, validate, insert, outbid notify
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
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Authentication required to place a bid.'
    );
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Enter a valid bid amount.'
    );
  END IF;

  SELECT a.auction_id,
         a.product_id,
         a.starting_price,
         a.minimum_increment,
         a.current_price,
         a.winner_id,
         a.starts_at,
         a.ends_at,
         a.status,
         p.seller_id,
         p.name AS product_name
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

  IF v_auction.seller_id = v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Sellers cannot bid on their own listings.'
    );
  END IF;

  IF v_auction.status = 'cancelled'::auction_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This auction was cancelled.'
    );
  END IF;

  IF v_auction.status <> 'active'::auction_status_enum
     OR v_auction.ends_at <= now() THEN
    PERFORM public.close_auctions();
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This auction has already ended.'
    );
  END IF;

  IF v_auction.starts_at > now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This auction has not started yet.'
    );
  END IF;

  v_min_bid := COALESCE(v_auction.current_price, v_auction.starting_price, 0)
    + COALESCE(v_auction.minimum_increment, 0);

  IF COALESCE(v_auction.minimum_increment, 0) <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This auction has an invalid bid increment.'
    );
  END IF;

  IF p_amount < v_min_bid THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Bid must be at least ' || v_min_bid::text
    );
  END IF;

  SELECT b.bidder_id
  INTO v_prev_bidder
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.is_highest_bid = true
  LIMIT 1;

  UPDATE public.bids
  SET is_highest_bid = false,
      updated_at = now()
  WHERE auction_id = p_auction_id
    AND is_highest_bid = true;

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

  SELECT count(*)::integer INTO v_count
  FROM public.bids
  WHERE auction_id = p_auction_id;

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
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric) TO authenticated, postgres, service_role;

-- ===========================================================================
-- 6. ensure_product_auction — seller-owned listing params, no bids overwrite
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_product_auction(
  p_product_id uuid,
  p_starting_price numeric,
  p_minimum_increment numeric,
  p_duration_days integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_product record;
  v_auction_id uuid;
  v_has_bids boolean;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  IF p_starting_price IS NULL OR p_starting_price <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid starting price.');
  END IF;

  IF p_minimum_increment IS NULL OR p_minimum_increment <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid bid increment.');
  END IF;

  IF p_duration_days IS NULL OR p_duration_days NOT IN (1, 3, 5, 7) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction duration must be 1, 3, 5, or 7 days.');
  END IF;

  SELECT product_id, seller_id, listing_type
  INTO v_product
  FROM public.products
  WHERE product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found.');
  END IF;

  IF v_product.seller_id IS DISTINCT FROM v_user_id AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can only create an auction for your own listing.');
  END IF;

  IF v_product.listing_type IS DISTINCT FROM 'auction'::listing_type_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing is not an auction.');
  END IF;

  SELECT auction_id INTO v_auction_id
  FROM public.auctions
  WHERE product_id = p_product_id
  LIMIT 1;

  IF v_auction_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.bids WHERE auction_id = v_auction_id
    ) INTO v_has_bids;

    IF v_has_bids THEN
      RETURN jsonb_build_object(
        'success', true,
        'auction_id', v_auction_id,
        'unchanged', true
      );
    END IF;

    v_starts_at := now();
    v_ends_at := v_starts_at + make_interval(days => p_duration_days);

    UPDATE public.auctions
    SET starting_price = p_starting_price,
        minimum_increment = p_minimum_increment,
        current_price = p_starting_price,
        duration_days = p_duration_days,
        starts_at = v_starts_at,
        ends_at = v_ends_at,
        status = 'active'::auction_status_enum,
        updated_at = now()
    WHERE auction_id = v_auction_id;

    RETURN jsonb_build_object('success', true, 'auction_id', v_auction_id);
  END IF;

  v_starts_at := now();
  v_ends_at := v_starts_at + make_interval(days => p_duration_days);

  BEGIN
    INSERT INTO public.auctions (
      product_id,
      starting_price,
      minimum_increment,
      current_price,
      starts_at,
      ends_at,
      status,
      duration_days,
      bid_count
    )
    VALUES (
      p_product_id,
      p_starting_price,
      p_minimum_increment,
      p_starting_price,
      v_starts_at,
      v_ends_at,
      'active'::auction_status_enum,
      p_duration_days,
      0
    )
    RETURNING auction_id INTO v_auction_id;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT auction_id INTO v_auction_id
      FROM public.auctions
      WHERE product_id = p_product_id
      LIMIT 1;
  END;

  RETURN jsonb_build_object('success', true, 'auction_id', v_auction_id);
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_product_auction(uuid, numeric, numeric, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_product_auction(uuid, numeric, numeric, integer)
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 7. v_user_bids — one row per (user, auction), status from DB clock
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
           ORDER BY hb.bid_amount DESC, hb.created_at ASC
           LIMIT 1
         )) IS NOT DISTINCT FROM b.bidder_id THEN 'won'
    WHEN a.status = 'active'::auction_status_enum AND a.ends_at <= now() THEN 'lost'
    WHEN b.is_highest_bid THEN 'winning'
    ELSE 'outbid'
  END AS bid_status
FROM (
  SELECT DISTINCT ON (bidder_id, auction_id)
    bid_id, auction_id, bidder_id, bid_amount, is_highest_bid, created_at
  FROM public.bids
  ORDER BY bidder_id, auction_id, bid_amount DESC, created_at DESC
) b
JOIN public.auctions a ON a.auction_id = b.auction_id
WHERE b.bidder_id = auth.uid() OR public.is_admin();

GRANT SELECT ON public.v_user_bids TO authenticated;

-- ===========================================================================
-- 8. RLS — bids are RPC-only writes; auctions writes are RPC-only
-- ===========================================================================

ALTER TABLE public.auctions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auctions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.bids ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bids FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bids_insert_own ON public.bids;
DROP POLICY IF EXISTS "bids_insert_own" ON public.bids;
-- Privilege, not this policy, blocks client inserts. place_bid is SECURITY
-- DEFINER; on Supabase, postgres is not a superuser so FORCE RLS still applies.
DROP POLICY IF EXISTS bids_insert_rpc ON public.bids;
CREATE POLICY bids_insert_rpc ON public.bids
  FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS bids_select_all ON public.bids;
CREATE POLICY bids_select_all ON public.bids
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS bids_update_admin ON public.bids;
DROP POLICY IF EXISTS bids_update_rpc ON public.bids;
CREATE POLICY bids_update_rpc ON public.bids
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS bids_delete_admin ON public.bids;
CREATE POLICY bids_delete_admin ON public.bids
  FOR DELETE
  USING (public.is_admin());

DROP POLICY IF EXISTS auctions_insert_own ON public.auctions;
DROP POLICY IF EXISTS auctions_insert_rpc ON public.auctions;
CREATE POLICY auctions_insert_rpc ON public.auctions
  FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS auctions_select_all ON public.auctions;
CREATE POLICY auctions_select_all ON public.auctions
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS auctions_update_own_admin ON public.auctions;
DROP POLICY IF EXISTS auctions_update_admin ON public.auctions;
DROP POLICY IF EXISTS auctions_update_rpc ON public.auctions;
CREATE POLICY auctions_update_rpc ON public.auctions
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS auctions_delete_admin ON public.auctions;
CREATE POLICY auctions_delete_admin ON public.auctions
  FOR DELETE
  USING (public.is_admin());

REVOKE ALL ON TABLE public.bids FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.bids TO anon, authenticated;
GRANT ALL ON TABLE public.bids TO postgres, service_role;

REVOKE ALL ON TABLE public.auctions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.auctions TO anon, authenticated;
GRANT ALL ON TABLE public.auctions TO postgres, service_role;

-- ===========================================================================
-- 9. Realtime publication (no-op if already added)
-- ===========================================================================

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
    NULL;
END;
$$;
