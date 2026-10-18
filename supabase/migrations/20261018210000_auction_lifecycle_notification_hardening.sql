-- Auction lifecycle: never roll back bids/settlement on notification failures;
-- never insert notifications with NULL audience.

-- ---------------------------------------------------------------------------
-- notifications: audience must never be NULL on insert
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notifications_set_audience_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.audience IS NULL THEN
    NEW.audience := COALESCE(
      public.infer_notification_audience(
        NEW.user_id,
        NEW.type,
        COALESCE(NEW.data, '{}'::jsonb)
      ),
      'system'::public.notification_audience_enum
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb,
  p_audience public.notification_audience_enum
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_audience public.notification_audience_enum;
BEGIN
  v_audience := COALESCE(
    p_audience,
    public.infer_notification_audience(
      p_user_id,
      p_type,
      COALESCE(p_data, '{}'::jsonb)
    ),
    'system'::public.notification_audience_enum
  );

  INSERT INTO public.notifications (user_id, type, title, body, data, audience)
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    COALESCE(p_data, '{}'::jsonb),
    v_audience
  )
  RETURNING notification_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_auction_event_once(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_auction_id uuid,
  p_event text,
  p_data jsonb DEFAULT '{}'::jsonb,
  p_audience public.notification_audience_enum DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_audience public.notification_audience_enum;
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

  v_audience := COALESCE(
    p_audience,
    public.infer_notification_audience(p_user_id, p_type, v_payload),
    'system'::public.notification_audience_enum
  );

  PERFORM public.notify_user(
    p_user_id,
    p_type,
    p_title,
    p_body,
    v_payload,
    v_audience
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- place_bid: bid commit must not fail when outbid notification insert fails
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.place_bid(
  p_auction_id uuid,
  p_amount numeric,
  p_device_token_hash text DEFAULT NULL
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
  v_status public.account_status_enum;
  v_restricted_until timestamptz;
  v_perm timestamptz;
  v_risk jsonb;
  v_current numeric;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required to place a bid.');
  END IF;

  IF NOT public.user_has_verified_account_phone(v_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'phone_verification_required',
      'error', 'Verify your phone number to place a bid.'
    );
  END IF;

  SELECT u.account_status INTO v_status
  FROM public.users u
  WHERE u.user_id = v_user_id;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Your account cannot place bids.');
  END IF;

  SELECT s.restricted_until, s.permanently_disabled_at
  INTO v_restricted_until, v_perm
  FROM public.auction_bidding_sanctions s
  WHERE s.user_id = v_user_id;

  IF v_perm IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Your account cannot place bids.');
  END IF;

  IF v_restricted_until IS NOT NULL AND v_restricted_until > now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',
      'Bidding is restricted until '
        || to_char(v_restricted_until, 'FMMon DD, YYYY, FMHH12:MI AM') || '.'
    );
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid bid amount.');
  END IF;

  PERFORM public.register_user_install_signal(
    v_user_id,
    p_device_token_hash,
    NULL
  );

  v_risk := public.evaluate_auction_bid_risk(
    v_user_id,
    p_auction_id,
    p_amount,
    p_device_token_hash
  );

  v_current := (
    SELECT COALESCE(a.current_price, a.starting_price, 0)
    FROM public.auctions a
    WHERE a.auction_id = p_auction_id
  );

  IF COALESCE((v_risk ->> 'allowed')::boolean, false) IS NOT TRUE THEN
    PERFORM public._log_auction_bid_risk_event(
      v_user_id,
      p_auction_id,
      NULL,
      p_amount,
      v_current,
      COALESCE(v_risk ->> 'risk_level', 'high'),
      COALESCE(v_risk -> 'reasons', '[]'::jsonb),
      'blocked',
      p_device_token_hash
    );
    RETURN jsonb_build_object(
      'success', false,
      'code', 'bid_risk_rejected',
      'error',
      'This bid could not be placed. If you believe this is an error, contact support.'
    );
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
    RETURN jsonb_build_object('success', false, 'error', 'Bid must be at least ' || to_char(v_min_bid, 'FM999999990.00'));
  END IF;

  SELECT b.bidder_id INTO v_prev_bidder
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
    AND b.is_highest_bid = true
  LIMIT 1;

  IF v_prev_bidder = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'You are already the highest bidder.');
  END IF;

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

  IF COALESCE(v_risk ->> 'action', 'allowed') = 'flagged' THEN
    PERFORM public._log_auction_bid_risk_event(
      v_user_id,
      p_auction_id,
      v_bid_id,
      p_amount,
      v_current,
      COALESCE(v_risk ->> 'risk_level', 'medium'),
      COALESCE(v_risk -> 'reasons', '[]'::jsonb),
      'flagged',
      p_device_token_hash
    );
  END IF;

  IF v_prev_bidder IS NOT NULL AND v_prev_bidder IS DISTINCT FROM v_user_id THEN
    BEGIN
      PERFORM public.notify_user(
        v_prev_bidder,
        'outbid',
        'You''ve been outbid',
        'Someone bid ' || to_char(p_amount, 'FM999999990.00') ||
          ' on ' || COALESCE(v_auction.product_name, 'an auction') || '.',
        jsonb_build_object(
          'auction_id', p_auction_id,
          'product_id', v_auction.product_id,
          'bid_id', v_bid_id,
          'amount', p_amount,
          'event', 'outbid'
        ),
        'buyer'::public.notification_audience_enum
      );
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'place_bid outbid notification failed for auction %: %', p_auction_id, SQLERRM;
    END;
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

REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric, text)
  TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- settle_one_auction: ended status must survive notification failures
-- ---------------------------------------------------------------------------

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
    BEGIN
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
        ),
        'buyer'::public.notification_audience_enum
      );
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'settle_one_auction won notification failed for %: %', p_auction_id, SQLERRM;
    END;
    BEGIN
      PERFORM public.ensure_auction_order(p_auction_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'ensure_auction_order failed for auction %: %', p_auction_id, SQLERRM;
    END;
  ELSIF v_auction.seller_id IS NOT NULL THEN
    BEGIN
      PERFORM public.notify_auction_event_once(
        v_auction.seller_id,
        'system',
        'Auction Ended — No Winner',
        COALESCE(v_auction.product_name, 'Your listing') || ' ended with no bids. You can relist the item.',
        p_auction_id,
        'seller_ended_no_bids',
        jsonb_build_object('product_id', v_auction.product_id),
        'seller'::public.notification_audience_enum
      );
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'settle_one_auction seller notification failed for %: %', p_auction_id, SQLERRM;
    END;
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.settle_one_auction(uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_one_auction(uuid, boolean) TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- ensure_my_auction_order: do not require line items in fallback lookup
-- ---------------------------------------------------------------------------

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
    PERFORM public.expire_auction_payment_offers();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'expire_auction_payment_offers in ensure_my_auction_order: %', SQLERRM;
  END;

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
      'Your pending order is not ready yet. We are still preparing it — please wait a moment and try again.'
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

-- Heal any auctions that should have ended (idempotent).
SELECT public.close_auctions();
