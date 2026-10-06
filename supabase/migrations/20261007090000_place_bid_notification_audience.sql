-- Fix place_bid outbid notifications: notifications.audience is NOT NULL.
-- Ensures notify_user always persists audience and place_bid sets buyer explicitly.

-- ---------------------------------------------------------------------------
-- notify_user: never insert NULL audience (explicit or inferred)
-- ---------------------------------------------------------------------------

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
    )
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

DROP FUNCTION IF EXISTS public.notify_user(uuid, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.notify_user(
    p_user_id,
    p_type,
    p_title,
    p_body,
    COALESCE(p_data, '{}'::jsonb),
    public.infer_notification_audience(
      p_user_id,
      p_type,
      COALESCE(p_data, '{}'::jsonb)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_user(uuid, text, text, text, jsonb, notification_audience_enum)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_user(uuid, text, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_user(uuid, text, text, text, jsonb, notification_audience_enum)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.notify_user(uuid, text, text, text, jsonb)
  TO postgres, service_role;

-- Safety net for any legacy INSERT path that omits audience.
CREATE OR REPLACE FUNCTION public.notifications_set_audience_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.audience IS NULL THEN
    NEW.audience := public.infer_notification_audience(
      NEW.user_id,
      NEW.type,
      COALESCE(NEW.data, '{}'::jsonb)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_set_audience ON public.notifications;
CREATE TRIGGER trg_notifications_set_audience
BEFORE INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.notifications_set_audience_before_insert();

-- ---------------------------------------------------------------------------
-- place_bid: explicit buyer audience on outbid notification
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.place_bid(uuid, numeric);

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
