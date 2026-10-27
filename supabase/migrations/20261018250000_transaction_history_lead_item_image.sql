-- Match product title + image to the same order line item (deterministic pick).

DROP FUNCTION IF EXISTS public.list_my_payment_transactions();

CREATE OR REPLACE FUNCTION public.list_my_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  product_image_url text,
  paid_at timestamptz,
  amount_centavos integer,
  payment_status text,
  payment_method text,
  paymongo_channel text,
  transaction_reference text,
  refunded_at timestamptz,
  refund_amount_centavos integer,
  refund_provider_status text,
  escrow_id uuid,
  refund_state text,
  refund_completed_at timestamptz,
  refund_transfer_link text,
  refund_transfer_link_expires_at timestamptz,
  refund_gcash_submitted boolean,
  manual_refund_reference text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.payment_id,
    o.order_id,
    o.order_number::text,
    COALESCE(lead_oi.title, 'Order'::text) AS product_title,
    COALESCE(
      lead_oi.item_image_url,
      (
        SELECT NULLIF(btrim(pi.image_url::text), '')
        FROM public.product_images pi
        WHERE pi.product_id = lead_oi.product_id
        ORDER BY pi.is_primary DESC, pi.display_order ASC, pi.created_at ASC
        LIMIT 1
      )
    ) AS product_image_url,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    p.payment_status::text,
    p.payment_method::text,
    p.paymongo_channel::text,
    p.transaction_reference::text,
    e.refunded_at,
    CASE
      WHEN e.status = 'refunded'::public.escrow_status_enum
        THEN COALESCE(e.amount_centavos, p.amount_centavos)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text,
    e.escrow_id,
    e.refund_state::text,
    e.refund_completed_at,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link
      ELSE NULL
    END AS refund_transfer_link,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link_expires_at
      ELSE NULL
    END AS refund_transfer_link_expires_at,
    (d.gcash_submitted_at IS NOT NULL) AS refund_gcash_submitted,
    d.manual_reference AS manual_refund_reference
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN LATERAL (
    SELECT
      oi.title::text AS title,
      oi.product_id,
      NULLIF(btrim(oi.image_url::text), '') AS item_image_url
    FROM public.order_items oi
    WHERE oi.order_id = o.order_id
    ORDER BY
      oi.line_total DESC NULLS LAST,
      oi.created_at ASC,
      oi.order_item_id ASC
    LIMIT 1
  ) lead_oi ON TRUE
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
  LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
  WHERE o.buyer_id = v_uid
    AND p.payment_status IN (
      'paid'::public.payment_status_enum,
      'refunded'::public.payment_status_enum
    )
  ORDER BY COALESCE(e.refunded_at, public.order_paid_at(o.order_id), p.updated_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_payment_transactions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_payment_transactions()
  TO authenticated, postgres, service_role;

DROP FUNCTION IF EXISTS public.list_my_seller_payment_transactions();

CREATE FUNCTION public.list_my_seller_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  product_image_url text,
  paid_at timestamptz,
  amount_centavos integer,
  seller_amount_centavos integer,
  subtotal_centavos integer,
  shipping_fee_centavos integer,
  commission_rate numeric,
  commission_amount_centavos integer,
  commission_status text,
  order_status text,
  payment_status text,
  payment_method text,
  paymongo_channel text,
  transaction_reference text,
  refunded_at timestamptz,
  refund_amount_centavos integer,
  refund_provider_status text,
  escrow_id uuid,
  escrow_status text,
  refund_state text,
  refund_completed_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.payment_id,
    o.order_id,
    o.order_number::text,
    COALESCE(lead_oi.title, 'Order'::text) AS product_title,
    COALESCE(
      lead_oi.item_image_url,
      (
        SELECT NULLIF(btrim(pi.image_url::text), '')
        FROM public.product_images pi
        WHERE pi.product_id = lead_oi.product_id
        ORDER BY pi.is_primary DESC, pi.display_order ASC, pi.created_at ASC
        LIMIT 1
      )
    ) AS product_image_url,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    COALESCE(e.seller_amount_centavos, 0) AS seller_amount_centavos,
    ROUND(COALESCE(o.subtotal, 0) * 100)::integer AS subtotal_centavos,
    ROUND(COALESCE(o.shipping_fee, 0) * 100)::integer AS shipping_fee_centavos,
    COALESCE(o.seller_commission_rate, 0.05) AS commission_rate,
    ROUND(COALESCE(o.seller_commission_amount, 0) * 100)::integer AS commission_amount_centavos,
    o.seller_commission_status::text,
    o.order_status::text,
    p.payment_status::text,
    p.payment_method::text,
    p.paymongo_channel::text,
    p.transaction_reference::text,
    e.refunded_at,
    CASE
      WHEN e.status = 'refunded'::public.escrow_status_enum
        THEN COALESCE(e.seller_amount_centavos, 0)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text,
    e.escrow_id,
    e.status::text AS escrow_status,
    e.refund_state::text,
    e.refund_completed_at
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN LATERAL (
    SELECT
      oi.title::text AS title,
      oi.product_id,
      NULLIF(btrim(oi.image_url::text), '') AS item_image_url
    FROM public.order_items oi
    WHERE oi.order_id = o.order_id
    ORDER BY
      oi.line_total DESC NULLS LAST,
      oi.created_at ASC,
      oi.order_item_id ASC
    LIMIT 1
  ) lead_oi ON TRUE
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
  WHERE o.seller_id = v_uid
    AND p.payment_status IN (
      'paid'::public.payment_status_enum,
      'refunded'::public.payment_status_enum
    )
  ORDER BY COALESCE(e.refunded_at, public.order_paid_at(o.order_id), p.updated_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_seller_payment_transactions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_seller_payment_transactions()
  TO authenticated, postgres, service_role;
