-- Auction winner non-payment violations, automatic second-chance fallback,
-- distinct second-highest bidder selection, and optional decline.
--
-- Builds on orders.auction_offer_rank (1 = primary winner, 2 = second chance),
-- expire_auction_payment_offers(), and PayMongo payment authority.

-- ---------------------------------------------------------------------------
-- Violation records (immutable audit trail)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.auction_bidding_violations (
  violation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  auction_id uuid NOT NULL REFERENCES public.auctions (auction_id) ON DELETE RESTRICT,
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE RESTRICT,
  bid_round integer NOT NULL CHECK (bid_round >= 1),
  violation_number integer NOT NULL CHECK (violation_number >= 1),
  payment_due_at timestamptz NOT NULL,
  expired_at timestamptz NOT NULL DEFAULT now(),
  consequence text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS auction_bidding_violations_auction_round_once
  ON public.auction_bidding_violations (auction_id, bid_round);

CREATE INDEX IF NOT EXISTS auction_bidding_violations_user_created_idx
  ON public.auction_bidding_violations (user_id, created_at DESC);

ALTER TABLE public.auction_bidding_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auction_bidding_violations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auction_bidding_violations_select_own_or_admin
  ON public.auction_bidding_violations;
CREATE POLICY auction_bidding_violations_select_own_or_admin
  ON public.auction_bidding_violations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

REVOKE ALL ON public.auction_bidding_violations FROM PUBLIC, anon;
GRANT SELECT ON public.auction_bidding_violations TO authenticated;

-- ---------------------------------------------------------------------------
-- Sanctions (server-authoritative restriction / disable state)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.auction_bidding_sanctions (
  user_id uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE RESTRICT,
  violation_count integer NOT NULL DEFAULT 0 CHECK (violation_count >= 0),
  restricted_until timestamptz,
  permanently_disabled_at timestamptz,
  disable_reason text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.auction_bidding_sanctions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auction_bidding_sanctions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auction_bidding_sanctions_select_own_or_admin
  ON public.auction_bidding_sanctions;
CREATE POLICY auction_bidding_sanctions_select_own_or_admin
  ON public.auction_bidding_sanctions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

REVOKE ALL ON public.auction_bidding_sanctions FROM PUBLIC, anon;
GRANT SELECT ON public.auction_bidding_sanctions TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_auction_bidding_permanent_disable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.auction_bidding_sanctions s
    WHERE s.user_id = NEW.user_id
      AND s.permanently_disabled_at IS NOT NULL
  ) THEN
    NEW.account_status := 'banned'::public.account_status_enum;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_auction_bidding_permanent_disable ON public.users;
CREATE TRIGGER trg_users_auction_bidding_permanent_disable
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.enforce_auction_bidding_permanent_disable();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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
      AND s.permanently_disabled_at IS NULL
      AND (s.restricted_until IS NULL OR s.restricted_until <= now())
    ORDER BY b.bidder_id, b.bid_amount DESC, b.created_at ASC
  )
  SELECT p.bid_id, p.bidder_id, p.bid_amount
  FROM per_bidder p
  ORDER BY p.bid_amount DESC, p.created_at ASC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.auction_pick_second_eligible_bidder(uuid, integer, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auction_pick_second_eligible_bidder(uuid, integer, uuid, uuid)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.record_auction_winner_non_payment(
  p_user_id uuid,
  p_auction_id uuid,
  p_order_id uuid,
  p_bid_round integer,
  p_payment_due_at timestamptz
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
  v_restricted_until timestamptz;
BEGIN
  IF p_user_id IS NULL OR p_auction_id IS NULL OR p_order_id IS NULL THEN
    RETURN 0;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.auction_bidding_violations v
    WHERE v.auction_id = p_auction_id
      AND v.bid_round = p_bid_round
  ) THEN
    SELECT s.violation_count INTO v_count
    FROM public.auction_bidding_sanctions s
    WHERE s.user_id = p_user_id;
    RETURN COALESCE(v_count, 0);
  END IF;

  SELECT count(*) + 1 INTO v_count
  FROM public.auction_bidding_violations v
  WHERE v.user_id = p_user_id;

  INSERT INTO public.auction_bidding_violations (
    user_id,
    auction_id,
    order_id,
    bid_round,
    violation_number,
    payment_due_at,
    expired_at,
    consequence
  )
  VALUES (
    p_user_id,
    p_auction_id,
    p_order_id,
    p_bid_round,
    v_count,
    p_payment_due_at,
    now(),
    CASE
      WHEN v_count = 1 THEN 'warning'
      WHEN v_count = 2 THEN 'bidding_restricted_3_days'
      ELSE 'account_disabled'
    END
  );

  INSERT INTO public.auction_bidding_sanctions AS s (
    user_id, violation_count, updated_at
  )
  VALUES (p_user_id, v_count, now())
  ON CONFLICT (user_id) DO UPDATE
  SET violation_count = EXCLUDED.violation_count,
      updated_at = now();

  IF v_count = 1 THEN
    PERFORM public.notify_user(
      p_user_id,
      'system',
      'Auction payment window expired',
      'You did not complete payment for an auction you won. This is your first bidding violation. Repeated non-payment may restrict your bidding access.',
      jsonb_build_object(
        'auction_id', p_auction_id,
        'order_id', p_order_id,
        'violation_number', 1,
        'event', 'auction_non_payment_violation'
      )
    );
  ELSIF v_count = 2 THEN
    v_restricted_until := now() + interval '3 days';
    UPDATE public.auction_bidding_sanctions
    SET restricted_until = v_restricted_until,
        updated_at = now()
    WHERE user_id = p_user_id;

    PERFORM public.notify_user(
      p_user_id,
      'system',
      'Auction payment window expired',
      'You did not complete payment for an auction you won. Bidding is restricted until '
        || to_char(v_restricted_until, 'FMMon DD, YYYY, FMHH12:MI AM') || '.',
      jsonb_build_object(
        'auction_id', p_auction_id,
        'order_id', p_order_id,
        'violation_number', 2,
        'restricted_until', v_restricted_until,
        'event', 'auction_non_payment_violation'
      )
    );
  ELSE
    UPDATE public.auction_bidding_sanctions
    SET
      permanently_disabled_at = COALESCE(permanently_disabled_at, now()),
      restricted_until = NULL,
      disable_reason = 'Repeated confirmed auction winner non-payment',
      updated_at = now()
    WHERE user_id = p_user_id;

    UPDATE public.users
    SET account_status = 'banned'::public.account_status_enum
    WHERE user_id = p_user_id;

    PERFORM public._looking_for_disable_auth_user(p_user_id);
    PERFORM public._looking_for_drop_auth_sessions(p_user_id);

    PERFORM public.notify_user(
      p_user_id,
      'system',
      'Account disabled',
      'Your account has been permanently disabled after repeated auction non-payment violations.',
      jsonb_build_object(
        'auction_id', p_auction_id,
        'order_id', p_order_id,
        'violation_number', v_count,
        'event', 'auction_non_payment_violation'
      )
    );
  END IF;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.record_auction_winner_non_payment(uuid, uuid, uuid, integer, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_auction_winner_non_payment(uuid, uuid, uuid, integer, timestamptz)
  TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- Second-chance decline (optional offer; no violation)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.decline_auction_second_chance(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
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

  IF v_order.buyer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'This offer is not for your account.');
  END IF;

  IF v_order.auction_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'This is not an auction order.');
  END IF;

  IF COALESCE(v_order.auction_offer_rank, 1) <> 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'There is no second-chance offer to decline.');
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This offer is no longer available.');
  END IF;

  IF v_order.payment_due_at IS NOT NULL AND v_order.payment_due_at <= now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'This offer has expired.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = v_order.order_id
      AND p.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order is already paid.');
  END IF;

  PERFORM public._close_unsold_auction_offer(v_order.order_id);

  RETURN jsonb_build_object('success', true, 'order_id', v_order.order_id);
END;
$$;

REVOKE ALL ON FUNCTION public.decline_auction_second_chance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decline_auction_second_chance(uuid)
  TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- Payment expiry: primary violation + automatic second chance
-- ---------------------------------------------------------------------------

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
      payment_due_at = now(),
      updated_at = now()
  WHERE order_id = p_order_id
    AND order_status = 'pending'::order_status_enum;

  UPDATE public.payments
  SET payment_status = 'failed'::payment_status_enum,
      updated_at = now()
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

  IF COALESCE(v_order.auction_offer_rank, 1) = 2 THEN
    PERFORM public.notify_user(
      v_order.buyer_id,
      'system',
      'Second chance offer closed',
      'You declined or did not complete payment for '
        || COALESCE(v_name, 'this auction item') || '.',
      jsonb_build_object(
        'order_id', p_order_id,
        'auction_id', v_order.auction_id,
        'event', 'auction_second_chance_closed'
      )
    );
  ELSE
    PERFORM public.notify_user(
      v_order.buyer_id,
      'system',
      'Payment window ended',
      'The payment window for ' || COALESCE(v_name, 'this auction') ||
        ' has ended. The item was not purchased.',
      jsonb_build_object('order_id', p_order_id, 'auction_id', v_order.auction_id)
    );
  END IF;

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Auction ended without a completed purchase',
    COALESCE(v_name, 'Your listing') ||
      ' was not paid for. It is now in Inactive Listings and can be edited and relisted.',
    jsonb_build_object(
      'order_id', p_order_id,
      'auction_id', v_order.auction_id,
      'event', 'auction_unpaid_inactive'
    )
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
  v_product public.products%ROWTYPE;
  v_next record;
  v_price numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_name text;
  v_count integer := 0;
  v_rank integer;
  v_exclude uuid;
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

    SELECT * INTO v_product
    FROM public.products
    WHERE product_id = v_auction.product_id;

    SELECT oi.title INTO v_name
    FROM public.order_items oi
    WHERE oi.order_id = v_order.order_id
    LIMIT 1;

    v_rank := COALESCE(v_order.auction_offer_rank, 1);

    IF v_rank = 1 THEN
      PERFORM public.record_auction_winner_non_payment(
        v_order.buyer_id,
        v_order.auction_id,
        v_order.order_id,
        COALESCE(v_auction.bid_round, 1),
        v_order.payment_due_at
      );

      v_exclude := v_order.buyer_id;

      SELECT * INTO v_next
      FROM public.auction_pick_second_eligible_bidder(
        v_order.auction_id,
        COALESCE(v_auction.bid_round, 1),
        v_exclude,
        v_product.seller_id
      );

      IF v_next.bidder_id IS NOT NULL THEN
        SELECT t.subtotal, t.shipping_fee, t.platform_fee, t.total_amount
        INTO v_price, v_shipping, v_platform, v_total
        FROM public.auction_checkout_total(v_next.bid_amount) t;

        UPDATE public.payments
        SET payment_status = 'failed'::payment_status_enum,
            updated_at = now()
        WHERE order_id = v_order.order_id
          AND payment_status = 'pending'::payment_status_enum;

        UPDATE public.orders
        SET buyer_id = v_next.bidder_id,
            subtotal = v_price,
            shipping_fee = v_shipping,
            platform_fee = v_platform,
            total_amount = v_total,
            payment_due_at = now() + interval '12 hours',
            auction_offer_rank = 2,
            passed_bidder_id = v_exclude,
            auction_offer_started_at = now(),
            updated_at = now()
        WHERE order_id = v_order.order_id;

        UPDATE public.order_items
        SET unit_price = v_price,
            line_total = v_price,
            updated_at = now()
        WHERE order_id = v_order.order_id;

        UPDATE public.auctions
        SET winner_id = v_next.bidder_id,
            winning_bid_id = v_next.bid_id,
            current_price = v_next.bid_amount,
            updated_at = now()
        WHERE auction_id = v_order.auction_id;

        PERFORM public.notify_user(
          v_order.seller_id,
          'system',
          'Second chance offer sent',
          'The original winner did not complete payment for '
            || COALESCE(v_name, 'your auction item')
            || '. The next eligible bidder has been notified.',
          jsonb_build_object(
            'auction_id', v_order.auction_id,
            'order_id', v_order.order_id,
            'event', 'auction_fallback_started'
          )
        );

        PERFORM public.notify_auction_event_once(
          v_next.bidder_id,
          'wonBid',
          'Second Chance Offer',
          'The original auction winner did not complete payment. You can purchase '
            || COALESCE(v_name, 'this item')
            || ' for your eligible bid amount of '
            || to_char(v_next.bid_amount, 'FM999999990.00')
            || '. You have 12 hours to accept and pay.',
          v_order.auction_id,
          'second_chance_offer',
          jsonb_build_object(
            'order_id', v_order.order_id,
            'amount', v_next.bid_amount,
            'event', 'second_chance_offer'
          )
        );
      ELSE
        PERFORM public._close_unsold_auction_offer(v_order.order_id);
      END IF;
    ELSE
      PERFORM public._close_unsold_auction_offer(v_order.order_id);
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_auction_payment_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_auction_payment_offers()
  TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- place_bid: enforce auction bidding sanctions
-- ---------------------------------------------------------------------------

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
  v_status public.account_status_enum;
  v_restricted_until timestamptz;
  v_perm timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required to place a bid.');
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

REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric)
  TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- v_user_bids: second-chance status + order fields
-- ---------------------------------------------------------------------------

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
  o.auction_offer_rank,
  o.order_id AS auction_order_id,
  CASE
    WHEN o.auction_offer_rank = 2
         AND o.order_status = 'pending'::order_status_enum
         AND o.payment_due_at IS NOT NULL
         AND o.payment_due_at > now()
         AND o.buyer_id = b.bidder_id
      THEN 'second_chance'
    WHEN a.status IN ('ended'::auction_status_enum, 'cancelled'::auction_status_enum)
         AND a.winner_id IS NOT NULL
         AND a.winner_id IS NOT DISTINCT FROM b.bidder_id
         AND o.order_status = 'pending'::order_status_enum
         AND o.payment_due_at IS NOT NULL
         AND o.payment_due_at > now()
         AND COALESCE(o.auction_offer_rank, 1) = 1
      THEN 'won'
    WHEN a.status IN ('ended'::auction_status_enum, 'cancelled'::auction_status_enum)
         AND a.winner_id IS NOT NULL
         AND a.winner_id IS NOT DISTINCT FROM b.bidder_id
      THEN 'won'
    WHEN a.status IN ('ended'::auction_status_enum, 'cancelled'::auction_status_enum)
      THEN 'lost'
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
