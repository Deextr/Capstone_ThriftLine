-- Auction bidding anti-abuse: verified phone gate, bid risk evaluation,
-- install signals, and admin-visible risk events.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Canonical verified-phone helper (align with unique index migration)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.user_has_verified_account_phone(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_user_id
      AND COALESCE(u.is_phone_verified, false)
      AND public.normalize_ph_mobile_storage(u.phone_number) IS NOT NULL
  );
$$;

REVOKE ALL ON FUNCTION public.user_has_verified_account_phone(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_verified_account_phone(uuid)
  TO authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- Install signal (hashed install token only)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.user_install_signals (
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  token_hash text NOT NULL,
  platform text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token_hash),
  CONSTRAINT user_install_signals_hash_chk
    CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT user_install_signals_platform_chk
    CHECK (platform IS NULL OR platform IN ('android', 'ios', 'other'))
);

CREATE INDEX IF NOT EXISTS user_install_signals_hash_idx
  ON public.user_install_signals (token_hash);

ALTER TABLE public.user_install_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_install_signals FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_install_signals_select_own_or_admin
  ON public.user_install_signals;
CREATE POLICY user_install_signals_select_own_or_admin
  ON public.user_install_signals
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

REVOKE ALL ON public.user_install_signals FROM PUBLIC, anon;
GRANT SELECT ON public.user_install_signals TO authenticated;

CREATE OR REPLACE FUNCTION public.normalize_device_token_hash(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_trim text;
BEGIN
  v_trim := lower(btrim(COALESCE(p_raw, '')));
  IF v_trim ~ '^[0-9a-f]{64}$' THEN
    RETURN v_trim;
  END IF;
  IF length(v_trim) >= 32 THEN
    RETURN encode(digest(v_trim, 'sha256'), 'hex');
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_user_install_signal(
  p_user_id uuid,
  p_token_hash text,
  p_platform text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hash text;
  v_platform text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;
  v_hash := public.normalize_device_token_hash(p_token_hash);
  IF v_hash IS NULL THEN
    RETURN;
  END IF;
  v_platform := CASE
    WHEN p_platform IN ('android', 'ios', 'other') THEN p_platform
    ELSE NULL
  END;
  INSERT INTO public.user_install_signals (
    user_id, token_hash, platform, first_seen_at, last_seen_at
  )
  VALUES (p_user_id, v_hash, v_platform, now(), now())
  ON CONFLICT (user_id, token_hash) DO UPDATE
  SET last_seen_at = now(),
      platform = COALESCE(EXCLUDED.platform, user_install_signals.platform);
END;
$$;

REVOKE ALL ON FUNCTION public.register_user_install_signal(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_user_install_signal(uuid, text, text)
  TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- Bid risk events (admin audit)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.auction_bid_risk_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  auction_id uuid NOT NULL REFERENCES public.auctions (auction_id) ON DELETE RESTRICT,
  bid_id uuid REFERENCES public.bids (bid_id) ON DELETE SET NULL,
  attempted_amount numeric(12, 2) NOT NULL,
  current_price numeric(12, 2),
  risk_level text NOT NULL,
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
  action_taken text NOT NULL,
  device_token_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auction_bid_risk_events_action_chk
    CHECK (action_taken IN ('allowed', 'blocked', 'flagged')),
  CONSTRAINT auction_bid_risk_events_level_chk
    CHECK (risk_level IN ('low', 'medium', 'high'))
);

CREATE INDEX IF NOT EXISTS auction_bid_risk_events_user_created_idx
  ON public.auction_bid_risk_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS auction_bid_risk_events_auction_created_idx
  ON public.auction_bid_risk_events (auction_id, created_at DESC);

ALTER TABLE public.auction_bid_risk_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auction_bid_risk_events FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auction_bid_risk_events_select_admin
  ON public.auction_bid_risk_events;
CREATE POLICY auction_bid_risk_events_select_admin
  ON public.auction_bid_risk_events
  FOR SELECT TO authenticated
  USING (public.is_admin());

REVOKE ALL ON public.auction_bid_risk_events FROM PUBLIC, anon;
GRANT SELECT ON public.auction_bid_risk_events TO authenticated;

CREATE OR REPLACE FUNCTION public._buyer_paid_order_count(p_user_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::integer
  FROM public.orders o
  WHERE o.buyer_id = p_user_id
    AND o.order_status = 'paid'::order_status_enum;
$$;

CREATE OR REPLACE FUNCTION public._log_auction_bid_risk_event(
  p_user_id uuid,
  p_auction_id uuid,
  p_bid_id uuid,
  p_attempted_amount numeric,
  p_current_price numeric,
  p_risk_level text,
  p_reasons jsonb,
  p_action text,
  p_device_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.auction_bid_risk_events (
    user_id,
    auction_id,
    bid_id,
    attempted_amount,
    current_price,
    risk_level,
    reasons,
    action_taken,
    device_token_hash
  )
  VALUES (
    p_user_id,
    p_auction_id,
    p_bid_id,
    p_attempted_amount,
    p_current_price,
    p_risk_level,
    COALESCE(p_reasons, '[]'::jsonb),
    p_action,
    public.normalize_device_token_hash(p_device_hash)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.evaluate_auction_bid_risk(
  p_user_id uuid,
  p_auction_id uuid,
  p_amount numeric,
  p_device_token_hash text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auction record;
  v_user record;
  v_paid integer;
  v_age interval;
  v_min_bid numeric;
  v_base numeric;
  v_ratio numeric;
  v_bids_1h integer;
  v_bids_24h integer;
  v_violations integer;
  v_banned_device integer;
  v_reasons jsonb := '[]'::jsonb;
  v_level text := 'low';
  v_action text := 'allowed';
  v_established boolean;
  v_device_hash text;
BEGIN
  SELECT a.starting_price, a.minimum_increment, a.current_price, a.bid_round
  INTO v_auction
  FROM public.auctions a
  WHERE a.auction_id = p_auction_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'risk_level', 'high',
      'reasons', jsonb_build_array('auction_not_found'),
      'action', 'blocked'
    );
  END IF;

  SELECT u.created_at INTO v_user
  FROM public.users u
  WHERE u.user_id = p_user_id;

  v_paid := public._buyer_paid_order_count(p_user_id);
  v_age := now() - COALESCE(v_user.created_at, now());
  v_established := v_paid > 0;

  v_min_bid := COALESCE(v_auction.current_price, v_auction.starting_price, 0)
    + COALESCE(v_auction.minimum_increment, 0);
  v_base := GREATEST(v_min_bid, COALESCE(v_auction.starting_price, 1), 1);
  v_ratio := p_amount / v_base;

  SELECT count(*)::integer INTO v_bids_1h
  FROM public.bids b
  WHERE b.bidder_id = p_user_id
    AND b.created_at > now() - interval '1 hour';

  SELECT count(*)::integer INTO v_bids_24h
  FROM public.bids b
  WHERE b.bidder_id = p_user_id
    AND b.created_at > now() - interval '24 hours';

  SELECT count(*)::integer INTO v_violations
  FROM public.auction_bidding_violations v
  WHERE v.user_id = p_user_id;

  v_device_hash := public.normalize_device_token_hash(p_device_token_hash);
  IF v_device_hash IS NOT NULL THEN
    SELECT count(DISTINCT s.user_id)::integer INTO v_banned_device
    FROM public.user_install_signals s
    JOIN public.users u ON u.user_id = s.user_id
    WHERE s.token_hash = v_device_hash
      AND u.account_status = 'banned'::public.account_status_enum
      AND s.user_id IS DISTINCT FROM p_user_id;
  ELSE
    v_banned_device := 0;
  END IF;

  IF v_ratio > 20 THEN
    v_reasons := v_reasons || jsonb_build_array('extreme_bid_jump');
    v_level := 'high';
  ELSIF v_ratio > 10 THEN
    v_reasons := v_reasons || jsonb_build_array('large_bid_jump');
    v_level := 'medium';
  END IF;

  IF v_age < interval '7 days' AND NOT v_established THEN
    v_reasons := v_reasons || jsonb_build_array('new_account');
  END IF;

  IF v_bids_1h >= 15 AND v_age < interval '1 day' THEN
    v_reasons := v_reasons || jsonb_build_array('high_bid_velocity_1h');
    v_level := 'high';
  ELSIF v_bids_24h >= 40 AND v_age < interval '3 days' AND NOT v_established THEN
    v_reasons := v_reasons || jsonb_build_array('high_bid_velocity_24h');
    v_level := 'medium';
  END IF;

  IF v_violations > 0 THEN
    v_reasons := v_reasons || jsonb_build_array('prior_auction_non_payment');
    IF v_level = 'low' THEN
      v_level := 'medium';
    END IF;
  END IF;

  IF v_banned_device > 0 THEN
    v_reasons := v_reasons || jsonb_build_array('device_linked_to_banned_account');
    IF v_level = 'low' THEN
      v_level := 'medium';
    END IF;
  END IF;

  -- Block new/low-history accounts on clear abuse patterns.
  IF (v_ratio > 20 AND NOT v_established AND v_age < interval '7 days')
     OR (v_ratio > 10 AND v_age < interval '1 day' AND NOT v_established)
     OR (v_bids_1h >= 15 AND v_age < interval '1 day')
     OR (v_banned_device > 0 AND NOT v_established AND v_ratio > 15) THEN
    v_action := 'blocked';
    v_level := 'high';
  ELSIF jsonb_array_length(v_reasons) > 0 AND v_established THEN
    v_action := 'flagged';
    IF v_level = 'low' THEN
      v_level := 'medium';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'allowed', v_action <> 'blocked',
    'risk_level', v_level,
    'reasons', v_reasons,
    'action', v_action,
    'jump_ratio', round(v_ratio, 2),
    'paid_orders', v_paid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.evaluate_auction_bid_risk(uuid, uuid, numeric, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_auction_bid_risk(uuid, uuid, numeric, text)
  TO postgres, service_role;

-- Second-chance: require verified phone
CREATE OR REPLACE FUNCTION public.auction_pick_second_eligible_bidder(
  p_auction_id uuid,
  p_bid_round integer,
  p_exclude_bidder_id uuid,
  p_seller_id uuid
)
RETURNS TABLE (
  bid_id uuid,
  bidder_id uuid,
  bid_amount numeric
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH per_bidder AS (
    SELECT DISTINCT ON (b.bidder_id)
      b.bid_id,
      b.bidder_id,
      b.bid_amount,
      b.created_at
    FROM public.bids b
    INNER JOIN public.users u ON u.user_id = b.bidder_id
    LEFT JOIN public.auction_bidding_sanctions s ON s.user_id = b.bidder_id
    WHERE b.auction_id = p_auction_id
      AND b.bid_round = p_bid_round
      AND b.bidder_id IS DISTINCT FROM p_exclude_bidder_id
      AND b.bidder_id IS DISTINCT FROM p_seller_id
      AND u.account_status = 'active'::public.account_status_enum
      AND public.user_has_verified_account_phone(b.bidder_id)
      AND s.permanently_disabled_at IS NULL
      AND (s.restricted_until IS NULL OR s.restricted_until <= now())
    ORDER BY b.bidder_id, b.bid_amount DESC, b.created_at ASC
  )
  SELECT p.bid_id, p.bidder_id, p.bid_amount
  FROM per_bidder p
  ORDER BY p.bid_amount DESC, p.created_at ASC
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- place_bid: phone verification + risk evaluation
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

REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric, text)
  TO authenticated, postgres, service_role;
