-- Migration: 20260911020000_listing_stock.sql
-- Description: Enforce listing stock (fixed-price variable, auction = 1)
--              on products, cart_items, add_to_cart, and checkout_cart.
-- Apply after 20260911010000_phase5_orders.sql. Do not rewrite that file.

-- ===========================================================================
-- 1. Auction listings cannot have more than one unit (0 after sold).
-- ===========================================================================

UPDATE public.products
SET quantity_available = 1
WHERE listing_type = 'auction'::listing_type_enum
  AND quantity_available > 1;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_auction_quantity_check;

ALTER TABLE public.products
  ADD CONSTRAINT products_auction_quantity_check
  CHECK (
    listing_type <> 'auction'::listing_type_enum
    OR quantity_available BETWEEN 0 AND 1
  );

CREATE OR REPLACE FUNCTION public.enforce_auction_listing_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.listing_type = 'auction'::listing_type_enum THEN
    IF NEW.quantity_available IS NULL OR NEW.quantity_available > 1 THEN
      NEW.quantity_available := 1;
    ELSIF NEW.quantity_available < 0 THEN
      NEW.quantity_available := 0;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_auction_stock ON public.products;
CREATE TRIGGER trg_products_auction_stock
  BEFORE INSERT OR UPDATE OF listing_type, quantity_available
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_auction_listing_stock();

-- ===========================================================================
-- 2. Shared max-purchasable helper (auction = 1, else live stock).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.max_purchasable_quantity(
  p_listing_type listing_type_enum,
  p_quantity_available integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN COALESCE(p_quantity_available, 0) <= 0 THEN 0
    WHEN p_listing_type = 'auction'::listing_type_enum THEN 1
    ELSE p_quantity_available
  END;
$$;

-- ===========================================================================
-- 3. Cart lines cannot exceed live product stock.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.enforce_cart_item_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_listing listing_type_enum;
  v_stock integer;
  v_max integer;
BEGIN
  SELECT p.listing_type, p.quantity_available
  INTO v_listing, v_stock
  FROM public.products p
  WHERE p.product_id = NEW.product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
  END IF;

  v_max := public.max_purchasable_quantity(v_listing, v_stock);

  IF NEW.quantity > v_max THEN
    RAISE EXCEPTION 'INSUFFICIENT_STOCK: only % available', v_max
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cart_items_stock ON public.cart_items;
CREATE TRIGGER trg_cart_items_stock
  BEFORE INSERT OR UPDATE OF product_id, quantity
  ON public.cart_items
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_cart_item_stock();

-- ===========================================================================
-- 4. add_to_cart caps against live stock (does not bypass the trigger).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.add_to_cart(
  p_product_id uuid,
  p_quantity integer DEFAULT 1
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_cart_item public.cart_items%ROWTYPE;
  v_listing listing_type_enum;
  v_stock integer;
  v_max integer;
  v_qty integer;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT p.listing_type, p.quantity_available
  INTO v_listing, v_stock
  FROM public.products p
  WHERE p.product_id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
  END IF;

  v_max := public.max_purchasable_quantity(v_listing, v_stock);
  IF v_max <= 0 THEN
    RAISE EXCEPTION 'INSUFFICIENT_STOCK: only 0 available';
  END IF;

  v_qty := LEAST(GREATEST(COALESCE(p_quantity, 1), 1), v_max);

  INSERT INTO public.cart_items (user_id, product_id, quantity)
  VALUES (v_user_id, p_product_id, v_qty)
  ON CONFLICT (user_id, product_id)
  DO UPDATE SET
    quantity = LEAST(public.cart_items.quantity + EXCLUDED.quantity, v_max),
    updated_at = now()
  RETURNING * INTO v_cart_item;

  RETURN row_to_json(v_cart_item);
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_to_cart(uuid, integer) TO authenticated;

-- ===========================================================================
-- 5. checkout_cart — clearer insufficient-stock error after row locks.
--    Signature stays checkout_cart(uuid, uuid, integer).
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
  v_avail integer;
  v_status product_status_enum;
  v_type listing_type_enum;
  v_price numeric(12, 2);
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

  -- Lock every product row we are about to buy (blocks concurrent checkouts).
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

REVOKE ALL ON FUNCTION public.checkout_cart(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkout_cart(uuid, uuid, integer)
  TO authenticated, postgres, service_role;
