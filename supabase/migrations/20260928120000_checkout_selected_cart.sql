-- Checkout only the cart lines the buyer selected.
-- Uses the same stock lock, one-seller order, and payment path as checkout_cart.
-- Idempotent. Do not edit earlier migrations.

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

  IF p_product_ids IS NULL OR cardinality(p_product_ids) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Select at least one item to check out.');
  END IF;

  SELECT * INTO v_address
  FROM public.addresses
  WHERE address_id = p_address_id
    AND user_id = v_buyer;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose one of your saved delivery addresses.');
  END IF;

  v_snapshot := public.order_address_snapshot(p_address_id);

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
    AND p.product_id = ANY(p_product_ids)
    AND p.listing_type = 'fixed_price'::listing_type_enum
    AND p.status = 'active'::product_status_enum
    AND p.seller_id IS DISTINCT FROM v_buyer;

  IF NOT EXISTS (SELECT 1 FROM tmp_checkout_lines) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your cart has no items that can be checked out.'
    );
  END IF;

  DELETE FROM tmp_checkout_lines
  WHERE seller_id IS DISTINCT FROM (
    SELECT t.seller_id
    FROM tmp_checkout_lines t
    ORDER BY t.seller_id
    LIMIT 1
  );

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

REVOKE ALL ON FUNCTION public.checkout_selected_cart(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkout_selected_cart(uuid, uuid[])
  TO authenticated, postgres, service_role;
