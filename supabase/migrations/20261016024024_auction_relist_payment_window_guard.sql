-- Block relist while the winner's 12-hour payment window (or pending payment) is active.
-- Ensures checkout orders exist before eligibility checks so sellers cannot skip the window.

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

  IF v_auction.winner_id IS NOT NULL THEN
    BEGIN
      PERFORM public.ensure_auction_order(v_auction.auction_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'ensure_auction_order during relist for %: %', v_auction.auction_id, SQLERRM;
    END;
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

  IF EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.payments pay ON pay.order_id = o.order_id
    WHERE o.auction_id = v_auction.auction_id
      AND o.order_status = 'pending'::order_status_enum
      AND pay.payment_status = 'pending'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'awaiting_winner_payment',
      'error', 'Awaiting winner payment: relisting is unavailable while payment is being processed.'
    );
  END IF;

  IF v_auction.winner_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.orders o
       JOIN public.payments pay ON pay.order_id = o.order_id
       WHERE o.auction_id = v_auction.auction_id
         AND pay.payment_status = 'paid'::payment_status_enum
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.orders o
       WHERE o.auction_id = v_auction.auction_id
         AND o.buyer_id = v_auction.winner_id
         AND o.order_status = 'cancelled'::order_status_enum
     ) THEN
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
    'bid_round', v_auction.bid_round + 1,
    'starting_price', v_new_start,
    'minimum_increment', v_new_incr,
    'ends_at', now() + make_interval(days => v_days)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.relist_unsold_auction(uuid, integer, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relist_unsold_auction(uuid, integer, numeric, numeric)
  TO authenticated, postgres, service_role;
