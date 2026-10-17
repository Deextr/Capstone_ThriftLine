-- Seller-side payment transaction history (orders where auth.uid() is seller).

CREATE OR REPLACE FUNCTION public.list_my_seller_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  paid_at timestamptz,
  amount_centavos integer,
  seller_amount_centavos integer,
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
    COALESCE(
      (
        SELECT oi.title::text
        FROM public.order_items oi
        WHERE oi.order_id = o.order_id
        ORDER BY oi.created_at
        LIMIT 1
      ),
      'Order'::text
    ) AS product_title,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    COALESCE(e.seller_amount_centavos, 0) AS seller_amount_centavos,
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

COMMENT ON FUNCTION public.list_my_seller_payment_transactions() IS
  'Paid and refunded orders for the authenticated seller (transaction history).';
