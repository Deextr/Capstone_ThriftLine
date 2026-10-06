-- Listing item location (privacy-safe) and seller-configurable shipping.
-- Architecture (see docs in COMMENT):
--   * Quantity free-shipping threshold is configured per listing but counts total
--     units from the same seller in checkout (same or different products).
--   * One shipping fee per seller order: MAX listing shipping_fee among paid modes,
--     unless all lines are free OR total qty meets the lowest active qty threshold.
--   * Auction shipping uses authoritative winning bid in auction_checkout_total().

DO $$
BEGIN
  CREATE TYPE public.listing_shipping_mode AS ENUM (
    'free',
    'fixed_fee',
    'quantity_threshold',
    'bid_threshold'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS show_item_location boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS shipping_mode public.listing_shipping_mode NOT NULL DEFAULT 'fixed_fee',
  ADD COLUMN IF NOT EXISTS shipping_fee numeric(12, 2) NOT NULL DEFAULT 80,
  ADD COLUMN IF NOT EXISTS free_shipping_qty_threshold integer,
  ADD COLUMN IF NOT EXISTS free_shipping_bid_threshold numeric(12, 2);

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_shipping_fee_positive;
ALTER TABLE public.products
  ADD CONSTRAINT products_shipping_fee_positive
  CHECK (shipping_fee >= 0);

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_free_shipping_qty_threshold_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_free_shipping_qty_threshold_check
  CHECK (
    free_shipping_qty_threshold IS NULL
    OR free_shipping_qty_threshold >= 2
  );

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_free_shipping_bid_threshold_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_free_shipping_bid_threshold_check
  CHECK (
    free_shipping_bid_threshold IS NULL
    OR free_shipping_bid_threshold > 0
  );

UPDATE public.products
SET
  shipping_mode = 'fixed_fee'::public.listing_shipping_mode,
  shipping_fee = 80
WHERE shipping_mode IS NULL;

COMMENT ON COLUMN public.products.show_item_location IS
  'When true, buyers see seller barangay + city only (from seller_profiles), not street address.';
COMMENT ON COLUMN public.products.shipping_mode IS
  'Fixed: free | fixed_fee | quantity_threshold. Auction: free | fixed_fee | bid_threshold.';
COMMENT ON COLUMN public.products.free_shipping_qty_threshold IS
  'Shop-wide for checkout: total units from this seller that qualify for free shipping.';

CREATE OR REPLACE FUNCTION public.format_public_item_location(p_seller_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN sp.barangay IS NULL OR btrim(sp.barangay) = '' THEN NULL
    ELSE btrim(sp.barangay) || ', '
      || COALESCE(NULLIF(btrim(sp.city), ''), 'Davao City')
  END
  FROM public.seller_profiles sp
  WHERE sp.seller_id = p_seller_id;
$$;

CREATE OR REPLACE FUNCTION public.calculate_shop_fixed_shipping(
  p_seller_id uuid,
  p_lines jsonb
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total_qty integer := 0;
  v_all_free boolean := true;
  v_has_paid boolean := false;
  v_max_fee numeric(12, 2) := 0;
  v_min_threshold integer;
  v_line record;
  v_mode public.listing_shipping_mode;
  v_fee numeric(12, 2);
  v_threshold integer;
BEGIN
  IF p_seller_id IS NULL OR p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN
    RETURN 80;
  END IF;

  FOR v_line IN
    SELECT
      (elem->>'product_id')::uuid AS product_id,
      GREATEST(COALESCE((elem->>'quantity')::integer, 0), 0) AS quantity
    FROM jsonb_array_elements(p_lines) AS elem
  LOOP
    IF v_line.product_id IS NULL OR v_line.quantity <= 0 THEN
      CONTINUE;
    END IF;

    SELECT p.shipping_mode, p.shipping_fee, p.free_shipping_qty_threshold
    INTO v_mode, v_fee, v_threshold
    FROM public.products p
    WHERE p.product_id = v_line.product_id
      AND p.seller_id = p_seller_id
      AND p.listing_type = 'fixed_price'::public.listing_type_enum;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid checkout line for seller.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_total_qty := v_total_qty + v_line.quantity;

    IF v_mode = 'free'::public.listing_shipping_mode THEN
      CONTINUE;
    END IF;

    v_all_free := false;
    v_has_paid := true;

    IF v_mode IN (
         'fixed_fee'::public.listing_shipping_mode,
         'quantity_threshold'::public.listing_shipping_mode
       ) THEN
      v_max_fee := GREATEST(v_max_fee, COALESCE(v_fee, 0));
    END IF;

    IF v_mode = 'quantity_threshold'::public.listing_shipping_mode
       AND v_threshold IS NOT NULL THEN
      v_min_threshold := LEAST(COALESCE(v_min_threshold, v_threshold), v_threshold);
    END IF;
  END LOOP;

  IF v_total_qty <= 0 THEN
    RETURN 0;
  END IF;

  IF v_all_free THEN
    RETURN 0;
  END IF;

  IF v_min_threshold IS NOT NULL AND v_total_qty >= v_min_threshold THEN
    RETURN 0;
  END IF;

  IF v_has_paid THEN
    RETURN GREATEST(v_max_fee, 0);
  END IF;

  RETURN 80;
END;
$$;

CREATE OR REPLACE FUNCTION public.auction_checkout_total(
  p_price numeric,
  p_product_id uuid DEFAULT NULL
)
RETURNS TABLE (
  subtotal numeric,
  shipping_fee numeric,
  platform_fee numeric,
  total_amount numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sub numeric;
  v_ship numeric := 80;
  v_plat numeric;
  v_mode public.listing_shipping_mode;
  v_fee numeric(12, 2);
  v_bid_threshold numeric(12, 2);
BEGIN
  v_sub := round(GREATEST(COALESCE(p_price, 0), 0), 2);

  IF p_product_id IS NOT NULL THEN
    SELECT shipping_mode, shipping_fee, free_shipping_bid_threshold
    INTO v_mode, v_fee, v_bid_threshold
    FROM public.products
    WHERE product_id = p_product_id;

    IF FOUND THEN
      v_ship := CASE v_mode
        WHEN 'free'::public.listing_shipping_mode THEN 0
        WHEN 'bid_threshold'::public.listing_shipping_mode THEN
          CASE
            WHEN v_bid_threshold IS NOT NULL AND v_sub >= v_bid_threshold THEN 0
            ELSE GREATEST(COALESCE(v_fee, 0), 0)
          END
        WHEN 'fixed_fee'::public.listing_shipping_mode THEN GREATEST(COALESCE(v_fee, 0), 0)
        ELSE 80
      END;
    END IF;
  END IF;

  v_plat := round(v_sub * 0.02, 2);
  subtotal := v_sub;
  shipping_fee := v_ship;
  platform_fee := v_plat;
  total_amount := v_sub + v_ship + v_plat;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.calculate_shop_fixed_shipping(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_shop_fixed_shipping(uuid, jsonb)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.format_public_item_location(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.format_public_item_location(uuid)
  TO authenticated, postgres, service_role;

DROP FUNCTION IF EXISTS public.auction_checkout_total(numeric);

REVOKE ALL ON FUNCTION public.auction_checkout_total(numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auction_checkout_total(numeric, uuid)
  TO postgres, service_role;

-- Patch checkout_selected_cart shipping (canonical version from 20261001180000).
CREATE OR REPLACE FUNCTION public.checkout_selected_cart(
  p_address_id uuid,
  p_product_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_address public.addresses%ROWTYPE;
  v_snapshot jsonb := '{}'::jsonb;
  v_seller uuid;
  v_order_id uuid;
  v_subtotal numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_created integer := 0;
  r record;
  v_avail integer;
  v_status product_status_enum;
  v_type listing_type_enum;
  v_price numeric(12, 2);
  v_lines jsonb;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to check out.');
  END IF;

  IF p_product_ids IS NULL OR cardinality(p_product_ids) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Select at least one item to check out.');
  END IF;

  IF p_address_id IS NOT NULL THEN
    SELECT * INTO v_address
    FROM public.addresses
    WHERE address_id = p_address_id
      AND user_id = v_buyer;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
    END IF;

    v_snapshot := public.order_address_snapshot(p_address_id);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_buyer::text));

  CREATE TEMP TABLE IF NOT EXISTS tmp_checkout_lines (
    product_id uuid PRIMARY KEY,
    seller_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    title text NOT NULL,
    image_url text,
    size text
  ) ON COMMIT DROP;

  DELETE FROM tmp_checkout_lines WHERE TRUE;

  INSERT INTO tmp_checkout_lines (
    product_id, seller_id, quantity, unit_price, title, image_url, size
  )
  SELECT
    p.product_id,
    p.seller_id,
    c.quantity,
    p.price,
    COALESCE(NULLIF(btrim(p.name), ''), 'Listing'),
    (
      SELECT pi.image_url
      FROM public.product_images pi
      WHERE pi.product_id = p.product_id
      ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
      LIMIT 1
    ),
    p.size
  FROM public.cart_items c
  JOIN public.products p ON p.product_id = c.product_id
  WHERE c.user_id = v_buyer
    AND p.product_id = ANY (p_product_ids)
    AND p.listing_type = 'fixed_price'::listing_type_enum
    AND p.status = 'active'::product_status_enum
    AND p.seller_id IS DISTINCT FROM v_buyer;

  IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Selected items are no longer available in your cart.'
    );
  END IF;

  PERFORM 1
  FROM public.products p
  JOIN tmp_checkout_lines t ON t.product_id = p.product_id
  FOR UPDATE OF p;

  FOR r IN SELECT * FROM tmp_checkout_lines
  LOOP
    IF r.seller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'A listing is missing its seller.');
    END IF;
    IF r.seller_id = v_buyer THEN
      RETURN jsonb_build_object('success', false, 'error', 'You cannot purchase your own listing.');
    END IF;

    SELECT p.quantity_available, p.status, p.listing_type, p.price
    INTO v_avail, v_status, v_type, v_price
    FROM public.products p
    WHERE p.product_id = r.product_id;

    IF v_status IS DISTINCT FROM 'active'::product_status_enum
       OR v_type IS DISTINCT FROM 'fixed_price'::listing_type_enum THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', COALESCE(r.title, 'This item') || ' is no longer available.'
      );
    END IF;

    IF v_price IS DISTINCT FROM r.unit_price THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'The price of ' || COALESCE(r.title, 'this item') ||
          ' has changed. Refresh your cart.'
      );
    END IF;

    IF COALESCE(v_avail, 0) < r.quantity THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Available stock has changed. Only ' ||
          COALESCE(v_avail, 0)::text || ' left of ' ||
          COALESCE(r.title, 'this item') ||
          '. Update the quantity and try again.'
      );
    END IF;
  END LOOP;

  FOR v_seller IN
    SELECT DISTINCT seller_id FROM tmp_checkout_lines ORDER BY seller_id
  LOOP
    SELECT COALESCE(sum(quantity * unit_price), 0)
    INTO v_subtotal
    FROM tmp_checkout_lines
    WHERE seller_id = v_seller;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object('product_id', t.product_id, 'quantity', t.quantity)
        ORDER BY t.product_id
      ),
      '[]'::jsonb
    )
    INTO v_lines
    FROM tmp_checkout_lines t
    WHERE t.seller_id = v_seller;

    v_shipping := public.calculate_shop_fixed_shipping(v_seller, v_lines);
    v_platform := round(v_subtotal * 0.02, 2);
    v_total := v_subtotal + v_shipping + v_platform;

    INSERT INTO public.orders (
      order_number, buyer_id, seller_id, order_type, order_status,
      subtotal, shipping_fee, platform_fee, total_amount, shipping_address
    )
    VALUES (
      public.next_order_number(),
      v_buyer,
      v_seller,
      'fixed_price'::order_type_enum,
      'pending'::order_status_enum,
      v_subtotal,
      v_shipping,
      v_platform,
      v_total,
      v_snapshot
    )
    RETURNING order_id INTO v_order_id;

    INSERT INTO public.order_items (
      order_id, product_id, title, image_url, size, unit_price, quantity, line_total
    )
    SELECT
      v_order_id, t.product_id, t.title, t.image_url, t.size,
      t.unit_price, t.quantity, round(t.unit_price * t.quantity, 2)
    FROM tmp_checkout_lines t
    WHERE t.seller_id = v_seller;

    FOR r IN
      SELECT product_id, quantity FROM tmp_checkout_lines WHERE seller_id = v_seller
    LOOP
      PERFORM public.consume_product_stock(r.product_id, r.quantity);
    END LOOP;

    v_order_ids := array_append(v_order_ids, v_order_id);
    v_created := v_created + 1;
  END LOOP;

  DELETE FROM public.cart_items c
  USING tmp_checkout_lines t
  WHERE c.user_id = v_buyer
    AND c.product_id = t.product_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_order_ids),
    'order_id', v_order_ids[1],
    'count', v_created
  );
END;
$$;

-- ensure_auction_order: pass product_id into auction_checkout_total (based on 20260930140000).
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
  FROM public.auction_checkout_total(v_auction.current_price, v_product.product_id) t;

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

  SELECT * INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id
  FOR UPDATE;

  IF v_existing.order_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.payments pay
      WHERE pay.order_id = v_existing.order_id
        AND pay.payment_status = 'paid'::payment_status_enum
    ) THEN
      RETURN v_existing.order_id;
    END IF;

    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'pending'::order_status_enum
       AND v_existing.payment_due_at IS NOT NULL
       AND v_existing.payment_due_at > now() THEN
      RETURN v_existing.order_id;
    END IF;

    IF v_existing.buyer_id = v_auction.winner_id
       AND v_existing.order_status = 'cancelled'::order_status_enum THEN
      RETURN NULL;
    END IF;

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

-- Second-chance: use product-aware shipping totals.
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
        FROM public.auction_checkout_total(v_next.bid_amount, v_product.product_id) t;

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

-- Buy Now / full-cart checkout: same per-seller shipping as checkout_selected_cart.
CREATE OR REPLACE FUNCTION public.checkout_cart(
  p_address_id uuid,
  p_product_id uuid DEFAULT NULL,
  p_quantity integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_address public.addresses%ROWTYPE;
  v_snapshot jsonb := '{}'::jsonb;
  v_seller uuid;
  v_order_id uuid;
  v_subtotal numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_created integer := 0;
  r record;
  v_avail integer;
  v_status product_status_enum;
  v_type listing_type_enum;
  v_price numeric(12, 2);
  v_lines jsonb;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to check out.');
  END IF;

  IF p_address_id IS NOT NULL THEN
    SELECT * INTO v_address
    FROM public.addresses
    WHERE address_id = p_address_id
      AND user_id = v_buyer;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
    END IF;

    v_snapshot := public.order_address_snapshot(p_address_id);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_buyer::text));

  CREATE TEMP TABLE IF NOT EXISTS tmp_checkout_lines (
    product_id uuid PRIMARY KEY,
    seller_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    title text NOT NULL,
    image_url text,
    size text
  ) ON COMMIT DROP;

  DELETE FROM tmp_checkout_lines WHERE TRUE;

  IF p_product_id IS NOT NULL THEN
    INSERT INTO tmp_checkout_lines (
      product_id, seller_id, quantity, unit_price, title, image_url, size
    )
    SELECT
      p.product_id,
      p.seller_id,
      c.quantity,
      p.price,
      COALESCE(NULLIF(btrim(p.name), ''), 'Listing'),
      (
        SELECT pi.image_url
        FROM public.product_images pi
        WHERE pi.product_id = p.product_id
        ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
        LIMIT 1
      ),
      p.size
    FROM public.products p
    JOIN public.cart_items c
      ON c.product_id = p.product_id AND c.user_id = v_buyer
    WHERE p.product_id = p_product_id
      AND p.listing_type = 'fixed_price'::listing_type_enum
      AND p.status = 'active'::product_status_enum;

    IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Add this item to your cart before checkout.'
      );
    END IF;
  ELSE
    INSERT INTO tmp_checkout_lines (
      product_id, seller_id, quantity, unit_price, title, image_url, size
    )
    SELECT
      p.product_id,
      p.seller_id,
      c.quantity,
      p.price,
      COALESCE(NULLIF(btrim(p.name), ''), 'Listing'),
      (
        SELECT pi.image_url
        FROM public.product_images pi
        WHERE pi.product_id = p.product_id
        ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
        LIMIT 1
      ),
      p.size
    FROM public.cart_items c
    JOIN public.products p ON p.product_id = c.product_id
    WHERE c.user_id = v_buyer
      AND p.listing_type = 'fixed_price'::listing_type_enum
      AND p.status = 'active'::product_status_enum
      AND p.seller_id IS DISTINCT FROM v_buyer;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your cart has no items that can be checked out.'
    );
  END IF;

  PERFORM 1
  FROM public.products p
  JOIN tmp_checkout_lines t ON t.product_id = p.product_id
  FOR UPDATE OF p;

  FOR r IN SELECT * FROM tmp_checkout_lines
  LOOP
    IF r.seller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'A listing is missing its seller.');
    END IF;
    IF r.seller_id = v_buyer THEN
      RETURN jsonb_build_object('success', false, 'error', 'You cannot purchase your own listing.');
    END IF;

    SELECT p.quantity_available, p.status, p.listing_type, p.price
    INTO v_avail, v_status, v_type, v_price
    FROM public.products p
    WHERE p.product_id = r.product_id;

    IF v_status IS DISTINCT FROM 'active'::product_status_enum
       OR v_type IS DISTINCT FROM 'fixed_price'::listing_type_enum THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', COALESCE(r.title, 'This item') || ' is no longer available.'
      );
    END IF;

    IF v_price IS DISTINCT FROM r.unit_price THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'The price of ' || COALESCE(r.title, 'this item') ||
          ' has changed. Refresh your cart.'
      );
    END IF;

    IF COALESCE(v_avail, 0) < r.quantity THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Available stock has changed. Only ' ||
          COALESCE(v_avail, 0)::text || ' left of ' ||
          COALESCE(r.title, 'this item') ||
          '. Update the quantity and try again.'
      );
    END IF;
  END LOOP;

  FOR v_seller IN
    SELECT DISTINCT seller_id FROM tmp_checkout_lines ORDER BY seller_id
  LOOP
    SELECT COALESCE(sum(quantity * unit_price), 0)
    INTO v_subtotal
    FROM tmp_checkout_lines
    WHERE seller_id = v_seller;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object('product_id', t.product_id, 'quantity', t.quantity)
        ORDER BY t.product_id
      ),
      '[]'::jsonb
    )
    INTO v_lines
    FROM tmp_checkout_lines t
    WHERE t.seller_id = v_seller;

    v_shipping := public.calculate_shop_fixed_shipping(v_seller, v_lines);
    v_platform := round(v_subtotal * 0.02, 2);
    v_total := v_subtotal + v_shipping + v_platform;

    INSERT INTO public.orders (
      order_number,
      buyer_id,
      seller_id,
      order_type,
      order_status,
      subtotal,
      shipping_fee,
      platform_fee,
      total_amount,
      shipping_address
    )
    VALUES (
      public.next_order_number(),
      v_buyer,
      v_seller,
      'fixed_price'::order_type_enum,
      'pending'::order_status_enum,
      v_subtotal,
      v_shipping,
      v_platform,
      v_total,
      v_snapshot
    )
    RETURNING order_id INTO v_order_id;

    INSERT INTO public.order_items (
      order_id, product_id, title, image_url, size, unit_price, quantity, line_total
    )
    SELECT
      v_order_id,
      t.product_id,
      t.title,
      t.image_url,
      t.size,
      t.unit_price,
      t.quantity,
      round(t.unit_price * t.quantity, 2)
    FROM tmp_checkout_lines t
    WHERE t.seller_id = v_seller;

    FOR r IN SELECT product_id, quantity FROM tmp_checkout_lines WHERE seller_id = v_seller
    LOOP
      PERFORM public.consume_product_stock(r.product_id, r.quantity);
    END LOOP;

    v_order_ids := array_append(v_order_ids, v_order_id);
    v_created := v_created + 1;
  END LOOP;

  DELETE FROM public.cart_items c
  USING tmp_checkout_lines t
  WHERE c.user_id = v_buyer
    AND c.product_id = t.product_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_order_ids),
    'order_id', v_order_ids[1],
    'count', v_created
  );
END;
$$;

REVOKE ALL ON FUNCTION public.checkout_cart(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkout_cart(uuid, uuid, integer)
  TO authenticated, postgres, service_role;

-- Seller manual second-chance offer: product-aware auction shipping.
CREATE OR REPLACE FUNCTION public.offer_auction_to_next_bidder(p_auction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_auction public.auctions%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_next_bid uuid;
  v_next_bidder uuid;
  v_next_amount numeric;
  v_price numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_name text;
  v_prev_winner uuid;
  v_address_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_image text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_auction_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction ID is required.');
  END IF;

  SELECT * INTO v_auction
  FROM public.auctions
  WHERE auction_id = p_auction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auction not found.');
  END IF;

  SELECT * INTO v_product
  FROM public.products
  WHERE product_id = v_auction.product_id;

  IF v_product.seller_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the seller can offer this auction to the next bidder.');
  END IF;

  IF v_auction.status IS DISTINCT FROM 'ended'::auction_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an ended auction can be offered to the next bidder.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.payments p ON p.order_id = o.order_id
    WHERE o.auction_id = p_auction_id AND p.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This auction was already paid.');
  END IF;

  PERFORM public.expire_auction_payment_offers();

  SELECT * INTO v_order
  FROM public.orders
  WHERE auction_id = p_auction_id
  FOR UPDATE;

  IF v_order.order_id IS NOT NULL
     AND v_order.order_status = 'pending'::order_status_enum
     AND v_order.payment_due_at > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'The current winner still has time to pay.');
  END IF;

  v_prev_winner := COALESCE(v_order.passed_bidder_id, v_order.buyer_id, v_auction.winner_id);

  SELECT b.bid_id, b.bidder_id, b.bid_amount
  INTO v_next_bid, v_next_bidder, v_next_amount
  FROM public.bids b
  WHERE b.auction_id = p_auction_id
    AND b.bid_round = v_auction.bid_round
    AND b.bidder_id IS DISTINCT FROM v_prev_winner
    AND b.bidder_id IS DISTINCT FROM v_uid
  ORDER BY b.bid_amount DESC, b.created_at ASC
  LIMIT 1;

  IF v_next_bidder IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No other valid bidders found for this auction. You can relist the item.');
  END IF;

  SELECT t.subtotal, t.shipping_fee, t.platform_fee, t.total_amount
  INTO v_price, v_shipping, v_platform, v_total
  FROM public.auction_checkout_total(v_next_amount, v_product.product_id) t;

  v_name := COALESCE(NULLIF(btrim(v_product.name), ''), 'this item');

  SELECT a.address_id INTO v_address_id
  FROM public.addresses a
  WHERE a.user_id = v_next_bidder
  ORDER BY a.is_default DESC, a.created_at DESC
  LIMIT 1;

  IF v_address_id IS NOT NULL THEN
    v_snapshot := public.order_address_snapshot(v_address_id);
  END IF;

  IF v_order.order_id IS NOT NULL THEN
    UPDATE public.payments
    SET payment_status = 'failed'::payment_status_enum
    WHERE order_id = v_order.order_id
      AND payment_status = 'pending'::payment_status_enum;

    UPDATE public.orders
    SET buyer_id = v_next_bidder,
        order_status = 'pending'::order_status_enum,
        subtotal = v_price,
        shipping_fee = v_shipping,
        platform_fee = v_platform,
        total_amount = v_total,
        shipping_address = v_snapshot,
        payment_due_at = now() + interval '12 hours',
        auction_offer_rank = 2,
        passed_bidder_id = v_prev_winner,
        auction_offer_started_at = now(),
        updated_at = now()
    WHERE order_id = v_order.order_id;

    UPDATE public.order_items
    SET unit_price = v_price,
        line_total = v_price
    WHERE order_id = v_order.order_id;
  ELSE
    SELECT pi.image_url INTO v_image
    FROM public.product_images pi
    WHERE pi.product_id = v_product.product_id
    ORDER BY pi.is_primary DESC NULLS LAST, pi.display_order ASC
    LIMIT 1;

    INSERT INTO public.orders (
      order_number, buyer_id, seller_id, auction_id, order_type, order_status,
      subtotal, shipping_fee, platform_fee, total_amount, shipping_address,
      payment_due_at, auction_offer_rank, auction_offer_started_at
    )
    VALUES (
      public.next_order_number(),
      v_next_bidder,
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
      2,
      now()
    )
    RETURNING order_id INTO v_order.order_id;

    INSERT INTO public.order_items (
      order_id, product_id, auction_id, title, image_url, size,
      unit_price, quantity, line_total
    )
    VALUES (
      v_order.order_id, v_product.product_id, p_auction_id, v_name, v_image,
      v_product.size, v_price, 1, v_price
    );
  END IF;

  PERFORM public.reserve_auction_unit(v_product.product_id);

  UPDATE public.auctions
  SET winner_id = v_next_bidder,
      winning_bid_id = v_next_bid,
      current_price = v_next_amount,
      updated_at = now()
  WHERE auction_id = p_auction_id;

  PERFORM public.notify_auction_event_once(
    v_next_bidder,
    'wonBid',
    'You can buy this auction',
    'The seller offered you ' || v_name ||
      ' for your bid of ₱' ||
      to_char(v_next_amount, 'FM999999990.00') ||
      '. Complete payment within 12 hours.',
    p_auction_id,
    'seller_fallback_offer',
    jsonb_build_object(
      'order_id', v_order.order_id,
      'amount', v_next_amount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'auction_id', p_auction_id,
    'order_id', v_order.order_id,
    'next_bidder_id', v_next_bidder,
    'amount', v_next_amount
  );
END;
$$;

REVOKE ALL ON FUNCTION public.offer_auction_to_next_bidder(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offer_auction_to_next_bidder(uuid)
  TO authenticated, postgres, service_role;
