-- Finalize expired auctions reliably and allow seller relist when eligible.
-- Fixes stale auctions stuck in status=active after ends_at, which blocked relist_unsold_auction.

-- ===========================================================================
-- 1. settle_one_auction: keep status=ended even if checkout order creation fails
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
    BEGIN
      PERFORM public.ensure_auction_order(p_auction_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'ensure_auction_order failed for auction %: %', p_auction_id, SQLERRM;
    END;
  ELSIF v_auction.seller_id IS NOT NULL THEN
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
-- 2. close_auctions: isolate failures so one bad auction does not block others
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
  FOR v_row IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'active'::auction_status_enum
      AND a.ends_at IS NOT NULL
      AND a.ends_at <= now()
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    BEGIN
      IF public.settle_one_auction(v_row.auction_id, false) THEN
        v_count := v_count + 1;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'settle_one_auction failed for auction %: %', v_row.auction_id, SQLERRM;
    END;
  END LOOP;

  FOR v_ended IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.orders oc
        WHERE oc.auction_id = a.auction_id
          AND oc.buyer_id = a.winner_id
          AND oc.order_status = 'cancelled'::order_status_enum
      )
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
    BEGIN
      PERFORM public.ensure_auction_order(v_ended.auction_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'ensure_auction_order failed for auction %: %', v_ended.auction_id, SQLERRM;
    END;
  END LOOP;

  BEGIN
    PERFORM public.expire_auction_payment_offers();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'expire_auction_payment_offers failed: %', SQLERRM;
  END;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.close_auctions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_auctions() TO authenticated, service_role, postgres;

-- ===========================================================================
-- 3. relist_unsold_auction: finalize expired rounds + clearer seller feedback
-- ===========================================================================

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
    RETURN jsonb_build_object(
      'success', false,
      'code', 'sign_in_required',
      'error', 'Please sign in.'
    );
  END IF;

  SELECT * INTO v_auction
  FROM public.auctions a
  WHERE a.product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'auction_not_found',
      'error', 'Auction not found.'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.products p
    WHERE p.product_id = p_product_id
      AND p.seller_id = v_uid
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_seller',
      'error', 'Only the seller can relist this auction.'
    );
  END IF;

  IF v_auction.status = 'active'::auction_status_enum THEN
    IF v_auction.ends_at IS NULL OR v_auction.ends_at > now() THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'auction_still_active',
        'error', 'Auction still active: this auction has not ended yet.'
      );
    END IF;

    PERFORM public.settle_one_auction(v_auction.auction_id, false);

    SELECT * INTO v_auction
    FROM public.auctions a
    WHERE a.product_id = p_product_id
    FOR UPDATE;
  END IF;

  IF v_auction.status IS DISTINCT FROM 'ended'::auction_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'auction_finalization_pending',
      'error', 'Auction finalization pending: please try again once the previous auction has been finalized.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.payments pay ON pay.order_id = o.order_id
    WHERE o.auction_id = v_auction.auction_id
      AND pay.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'auction_already_paid',
      'error', 'This auction was already paid and cannot be relisted.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.delivery_disputes d ON d.order_id = o.order_id
    WHERE o.auction_id = v_auction.auction_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'unresolved_dispute',
      'error', 'Relisting is unavailable while a delivery dispute for this auction is still open.'
    );
  END IF;

  BEGIN
    PERFORM public.expire_auction_payment_offers();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'expire_auction_payment_offers during relist: %', SQLERRM;
  END;

  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.auction_id = v_auction.auction_id
      AND o.order_status = 'pending'::order_status_enum
      AND (o.payment_due_at IS NULL OR o.payment_due_at > now())
      AND NOT EXISTS (
        SELECT 1 FROM public.payments pay
        WHERE pay.order_id = o.order_id
          AND pay.payment_status = 'paid'::payment_status_enum
      )
  ) INTO v_open_offer;

  IF v_open_offer THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'awaiting_winner_payment',
      'error', 'Awaiting winner payment: relisting is unavailable while the winning bidder''s payment window is active.'
    );
  END IF;

  UPDATE public.orders
  SET order_status = 'cancelled'::order_status_enum,
      updated_at = now()
  WHERE auction_id = v_auction.auction_id
    AND order_status = 'pending'::order_status_enum;

  BEGIN
    PERFORM public.assert_seller_active_listing_capacity(v_uid, p_product_id);
  EXCEPTION
    WHEN check_violation THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'listing_limit_reached',
        'error', SQLERRM
      );
  END;

  v_days := COALESCE(p_duration_days, v_auction.duration_days, 3);
  IF v_days NOT IN (1, 3, 5, 7) THEN
    v_days := 3;
  END IF;

  v_new_start := COALESCE(NULLIF(p_starting_price, 0), v_auction.starting_price);
  IF v_new_start IS NULL OR v_new_start <= 0 THEN
    v_new_start := v_auction.starting_price;
  END IF;

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

  UPDATE public.products
  SET price = v_new_start,
      status = 'active'::product_status_enum,
      updated_at = now()
  WHERE product_id = p_product_id;

  PERFORM public.release_auction_unit(p_product_id);

  RETURN jsonb_build_object(
    'success', true,
    'code', 'eligible_for_relist',
    'message', 'Eligible for relisting: the previous auction has ended, and this item can be listed for bidding again.',
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

-- ===========================================================================
-- 4. Backfill: settle auctions that should already be ended
-- ===========================================================================

DO $$
DECLARE
  r record;
BEGIN
  PERFORM public.close_auctions();
END;
$$;

-- ===========================================================================
-- 5. Optional pg_cron schedule (when extension is available)
-- ===========================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'thriftline-close-auctions'
    ) THEN
      PERFORM cron.schedule(
        'thriftline-close-auctions',
        '* * * * *',
        $cron$SELECT public.close_auctions();$cron$
      );
    END IF;
  END IF;
EXCEPTION
  WHEN undefined_table OR undefined_object THEN
    NULL;
  WHEN OTHERS THEN
    RAISE WARNING 'Could not schedule close_auctions cron job: %', SQLERRM;
END;
$$;
