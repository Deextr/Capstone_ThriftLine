-- Phase 5 — Cart → checkout → real orders.
--
-- Does NOT rewrite 20260907020000_cart_items.sql or Phase 3 auction files.
-- The foundation `orders` / `order_items` tables already exist (see supabase.txt):
--   orders: order_id, buyer_id, seller_id, order_type, order_status,
--           subtotal, platform_fee, total_amount, expires_at, timestamps
--   order_items: order_item_id, order_id, product_id, auction_id, unit_price
-- This file ADDS the checkout columns those tables are missing, then:
--   * checkout_cart() — server-priced, stock-locked, cart cleared in the same txn
--   * ensure_auction_order() — idempotent pending order for a winner
--   * extends close_auctions() to ensure that order
--
-- Do NOT recreate order_status_enum / payment_status_enum — they already exist
-- with different values (pending/paid/shipped/… and pending/paid/failed/…).
-- Phase 5 writes order_status = pending only. Never paid.
--
-- Idempotent. Safe to re-run after a failed attempt.

-- ===========================================================================
-- 1. Foundation tables (skip if the original schema already created them)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.orders (
  order_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  order_type public.order_type_enum NOT NULL,
  order_status public.order_status_enum NOT NULL DEFAULT 'pending',
  subtotal numeric NOT NULL,
  platform_fee numeric NOT NULL,
  total_amount numeric NOT NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_items (
  order_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products (product_id),
  auction_id uuid,
  unit_price numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.next_order_number()
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT 'TL-' || to_char(now() AT TIME ZONE 'UTC', 'YYMMDD') || '-' ||
         upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

-- ===========================================================================
-- 2. Columns the foundation tables do not have
-- ===========================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_number text,
  ADD COLUMN IF NOT EXISTS auction_id uuid,
  ADD COLUMN IF NOT EXISTS shipping_fee numeric(12, 2),
  ADD COLUMN IF NOT EXISTS shipping_address jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS tracking_number text,
  ADD COLUMN IF NOT EXISTS courier text;

UPDATE public.orders
SET order_number = public.next_order_number()
WHERE order_number IS NULL OR btrim(order_number) = '';

UPDATE public.orders
SET shipping_fee = 0
WHERE shipping_fee IS NULL;

ALTER TABLE public.orders
  ALTER COLUMN order_number SET NOT NULL,
  ALTER COLUMN shipping_fee SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE public.orders
    ADD CONSTRAINT orders_auction_id_fkey
    FOREIGN KEY (auction_id) REFERENCES public.auctions (auction_id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_table THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.orders
    ADD CONSTRAINT orders_buyer_not_seller CHECK (buyer_id <> seller_id);
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN check_violation THEN NULL;
END $$;

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS title text NOT NULL DEFAULT 'Item',
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS size text,
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS line_total numeric(12, 2);

UPDATE public.order_items
SET line_total = round(unit_price * COALESCE(quantity, 1), 2)
WHERE line_total IS NULL;

ALTER TABLE public.order_items
  ALTER COLUMN line_total SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS orders_order_number_key
  ON public.orders (order_number);

CREATE UNIQUE INDEX IF NOT EXISTS orders_auction_id_uidx
  ON public.orders (auction_id)
  WHERE auction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_buyer_created_idx
  ON public.orders (buyer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS orders_seller_created_idx
  ON public.orders (seller_id, created_at DESC);

CREATE INDEX IF NOT EXISTS orders_seller_status_idx
  ON public.orders (seller_id, order_status);

CREATE INDEX IF NOT EXISTS order_items_order_idx
  ON public.order_items (order_id);

CREATE INDEX IF NOT EXISTS order_items_product_idx
  ON public.order_items (product_id);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON public.orders;
CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- 3. RLS — clients SELECT only; writes go through DEFINER RPCs
-- ===========================================================================

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders FORCE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_delete_admin ON public.orders;
DROP POLICY IF EXISTS orders_insert_buyer ON public.orders;
DROP POLICY IF EXISTS orders_select_participant_admin ON public.orders;
DROP POLICY IF EXISTS orders_update_participant_admin ON public.orders;
DROP POLICY IF EXISTS order_items_delete_admin ON public.order_items;
DROP POLICY IF EXISTS order_items_insert_buyer ON public.order_items;
DROP POLICY IF EXISTS order_items_select_participant_admin ON public.order_items;
DROP POLICY IF EXISTS order_items_update_admin ON public.order_items;

DROP POLICY IF EXISTS orders_select_participant ON public.orders;
CREATE POLICY orders_select_participant ON public.orders
  FOR SELECT TO authenticated
  USING (
    auth.uid() = buyer_id
    OR auth.uid() = seller_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS orders_insert_postgres ON public.orders;
CREATE POLICY orders_insert_postgres ON public.orders
  FOR INSERT TO postgres
  WITH CHECK (true);

DROP POLICY IF EXISTS orders_update_postgres ON public.orders;
CREATE POLICY orders_update_postgres ON public.orders
  FOR UPDATE TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS order_items_select_participant ON public.order_items;
CREATE POLICY order_items_select_participant ON public.order_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = order_items.order_id
        AND (
          o.buyer_id = auth.uid()
          OR o.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

DROP POLICY IF EXISTS order_items_insert_postgres ON public.order_items;
CREATE POLICY order_items_insert_postgres ON public.order_items
  FOR INSERT TO postgres
  WITH CHECK (true);

DROP POLICY IF EXISTS products_update_postgres ON public.products;
CREATE POLICY products_update_postgres ON public.products
  FOR UPDATE TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.orders FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.orders TO postgres, service_role;

REVOKE ALL ON TABLE public.order_items FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.order_items TO authenticated;
GRANT ALL ON TABLE public.order_items TO postgres, service_role;

DO $$
BEGIN
  IF to_regclass('public.payments') IS NOT NULL THEN
    EXECUTE 'DROP POLICY IF EXISTS payments_insert_buyer ON public.payments';
    EXECUTE 'DROP POLICY IF EXISTS payments_delete_admin ON public.payments';
    REVOKE ALL ON TABLE public.payments FROM PUBLIC, anon, authenticated;
    GRANT SELECT ON TABLE public.payments TO authenticated;
    GRANT ALL ON TABLE public.payments TO postgres, service_role;
  END IF;
END $$;

-- ===========================================================================
-- 4. Helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.order_address_snapshot(p_address_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.addresses%ROWTYPE;
  v_formatted text;
BEGIN
  IF p_address_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT * INTO v_row
  FROM public.addresses
  WHERE address_id = p_address_id;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  v_formatted := concat_ws(
    ', ',
    NULLIF(btrim(v_row.street_address), ''),
    NULLIF(btrim(v_row.barangay), ''),
    NULLIF(btrim(v_row.city), ''),
    NULLIF(btrim(COALESCE(v_row.postal_code, '')), '')
  );

  RETURN jsonb_build_object(
    'address_id', v_row.address_id,
    'recipient_name', v_row.recipient_name,
    'phone_number', v_row.phone_number,
    'street_address', v_row.street_address,
    'barangay', v_row.barangay,
    'city', v_row.city,
    'postal_code', v_row.postal_code,
    'landmark', v_row.landmark,
    'formatted', v_formatted
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_product_stock(
  p_product_id uuid,
  p_quantity integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_qty integer;
BEGIN
  UPDATE public.products
  SET quantity_available = quantity_available - p_quantity,
      status = CASE
        WHEN quantity_available - p_quantity <= 0 THEN 'sold'::product_status_enum
        ELSE status
      END,
      sold_at = CASE
        WHEN quantity_available - p_quantity <= 0 THEN now()
        ELSE sold_at
      END
  WHERE product_id = p_product_id
    AND status = 'active'::product_status_enum
    AND quantity_available >= p_quantity
  RETURNING quantity_available INTO v_qty;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSUFFICIENT_STOCK';
  END IF;
END;
$$;

-- ===========================================================================
-- 5. checkout_cart
-- ===========================================================================

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
  v_snapshot jsonb;
  v_seller uuid;
  v_order_id uuid;
  v_subtotal numeric(12, 2);
  v_shipping numeric(12, 2);
  v_platform numeric(12, 2);
  v_total numeric(12, 2);
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_created integer := 0;
  r record;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to check out.');
  END IF;

  IF p_address_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Add a delivery address before checkout.');
  END IF;

  SELECT * INTO v_address
  FROM public.addresses
  WHERE address_id = p_address_id
    AND user_id = v_buyer;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
  END IF;

  v_snapshot := public.order_address_snapshot(p_address_id);

  -- Serialize this buyer's checkouts so a double-tap cannot split stock/cart.
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

  DELETE FROM tmp_checkout_lines;

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

  -- Lock every product row we are about to buy.
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
    IF NOT EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = r.product_id
        AND p.status = 'active'::product_status_enum
        AND p.listing_type = 'fixed_price'::listing_type_enum
        AND p.quantity_available >= r.quantity
        AND p.price = r.unit_price
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', COALESCE(r.title, 'A listing') ||
          ' is no longer available in that quantity or price. Refresh your cart.'
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

    v_shipping := 80;
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

    FOR r IN SELECT product_id, quantity, title FROM tmp_checkout_lines WHERE seller_id = v_seller
    LOOP
      PERFORM public.consume_product_stock(r.product_id, r.quantity);
    END LOOP;

    v_order_ids := array_append(v_order_ids, v_order_id);
    v_created := v_created + 1;

    PERFORM public.notify_user(
      v_buyer,
      'orderConfirmed',
      'Order placed',
      'Your order is waiting for payment.',
      jsonb_build_object('order_id', v_order_id)
    );
    PERFORM public.notify_user(
      v_seller,
      'system',
      'New order',
      'A buyer placed an order. Payment is still pending.',
      jsonb_build_object('order_id', v_order_id)
    );
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

-- ===========================================================================
-- 6. Auction win → pending order (idempotent)
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
  v_existing uuid;
  v_order_id uuid;
  v_price numeric(12, 2);
  v_platform numeric(12, 2);
  v_shipping numeric(12, 2) := 80;
  v_total numeric(12, 2);
  v_address_id uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_image text;
BEGIN
  IF p_auction_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT o.order_id INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT a.auction_id, a.product_id, a.winner_id, a.winning_bid_id, a.current_price, a.status
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

  SELECT o.order_id INTO v_existing
  FROM public.orders o
  WHERE o.auction_id = p_auction_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_price := COALESCE(v_auction.current_price, 0);
  IF v_price < 0 THEN
    v_price := 0;
  END IF;
  v_platform := round(v_price * 0.02, 2);
  v_total := v_price + v_shipping + v_platform;

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

  INSERT INTO public.orders (
    order_number,
    buyer_id,
    seller_id,
    auction_id,
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
    v_auction.winner_id,
    v_product.seller_id,
    p_auction_id,
    'auction'::order_type_enum,
    'pending'::order_status_enum,
    v_price,
    v_shipping,
    v_platform,
    v_total,
    v_snapshot
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
    order_id, product_id, auction_id, title, image_url, size, unit_price, quantity, line_total
  )
  VALUES (
    v_order_id,
    v_product.product_id,
    p_auction_id,
    COALESCE(NULLIF(btrim(v_product.name), ''), 'Auction listing'),
    v_image,
    v_product.size,
    v_price,
    1,
    v_price
  );

  BEGIN
    PERFORM public.consume_product_stock(v_product.product_id, 1);
  EXCEPTION
    WHEN others THEN
      UPDATE public.products
      SET status = 'sold'::product_status_enum,
          sold_at = COALESCE(sold_at, now())
      WHERE product_id = v_product.product_id;
  END;

  PERFORM public.notify_user(
    v_auction.winner_id,
    'orderConfirmed',
    'Auction order ready',
    'You won the auction. Complete payment when it is available.',
    jsonb_build_object('order_id', v_order_id, 'auction_id', p_auction_id)
  );
  PERFORM public.notify_user(
    v_product.seller_id,
    'system',
    'Auction sold',
    COALESCE(v_product.name, 'Your listing') || ' has a pending winner order.',
    jsonb_build_object('order_id', v_order_id, 'auction_id', p_auction_id)
  );

  RETURN v_order_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT o.order_id INTO v_order_id
    FROM public.orders o
    WHERE o.auction_id = p_auction_id;
    RETURN v_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_order_address(
  p_order_id uuid,
  p_address_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_snapshot jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status = 'cancelled'::order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order was cancelled.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.addresses a
    WHERE a.address_id = p_address_id
      AND a.user_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
  END IF;

  v_snapshot := public.order_address_snapshot(p_address_id);

  UPDATE public.orders
  SET shipping_address = v_snapshot
  WHERE order_id = p_order_id;

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;

-- ===========================================================================
-- 7. close_auctions — same settle logic, plus ensure_auction_order
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
  v_ended record;
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
      PERFORM public.ensure_auction_order(v_row.auction_id);
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

  FOR v_ended IN
    SELECT a.auction_id
    FROM public.auctions a
    WHERE a.status = 'ended'::auction_status_enum
      AND a.winner_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o WHERE o.auction_id = a.auction_id
      )
  LOOP
    PERFORM public.ensure_auction_order(v_ended.auction_id);
  END LOOP;

  RETURN v_count;
END;
$$;

-- ===========================================================================
-- 8. Grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.order_address_snapshot(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.order_address_snapshot(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.next_order_number() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_order_number() TO postgres, service_role;

REVOKE ALL ON FUNCTION public.consume_product_stock(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_product_stock(uuid, integer) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.checkout_cart(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkout_cart(uuid, uuid, integer)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.ensure_auction_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_auction_order(uuid)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.set_order_address(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_order_address(uuid, uuid)
  TO authenticated, postgres, service_role;
