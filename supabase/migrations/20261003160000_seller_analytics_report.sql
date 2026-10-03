-- Seller analytics: released earnings, completed orders, and quantities (auth-scoped).

CREATE OR REPLACE FUNCTION public.seller_analytics_report(
  p_range_start timestamptz DEFAULT NULL,
  p_range_end timestamptz DEFAULT NULL,
  p_compare_start timestamptz DEFAULT NULL,
  p_compare_end timestamptz DEFAULT NULL,
  p_include_compare boolean DEFAULT true,
  p_chart_bucket text DEFAULT 'day'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bucket text := lower(COALESCE(p_chart_bucket, 'day'));
  v_earnings bigint := 0;
  v_prev_earnings bigint := 0;
  v_products bigint := 0;
  v_prev_products bigint := 0;
  v_orders bigint := 0;
  v_prev_orders bigint := 0;
  v_chart jsonb := '[]'::jsonb;
  v_recent jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF v_bucket NOT IN ('day', 'month') THEN
    v_bucket := 'day';
  END IF;

  SELECT COALESCE(SUM(e.seller_amount_centavos), 0)
    INTO v_earnings
  FROM public.escrow e
  WHERE e.seller_id = v_uid
    AND e.status = 'released'::public.escrow_status_enum
    AND e.released_at IS NOT NULL
    AND (p_range_start IS NULL OR e.released_at >= p_range_start)
    AND (p_range_end IS NULL OR e.released_at < p_range_end);

  IF p_include_compare AND p_compare_start IS NOT NULL AND p_compare_end IS NOT NULL THEN
    SELECT COALESCE(SUM(e.seller_amount_centavos), 0)
      INTO v_prev_earnings
    FROM public.escrow e
    WHERE e.seller_id = v_uid
      AND e.status = 'released'::public.escrow_status_enum
      AND e.released_at IS NOT NULL
      AND e.released_at >= p_compare_start
      AND e.released_at < p_compare_end;
  END IF;

  SELECT COALESCE(SUM(oi.quantity), 0),
         COUNT(DISTINCT o.order_id)
    INTO v_products, v_orders
  FROM public.orders o
  JOIN public.order_items oi ON oi.order_id = o.order_id
  JOIN public.shipments s ON s.order_id = o.order_id
  WHERE o.seller_id = v_uid
    AND o.order_status = 'completed'::public.order_status_enum
    AND s.completed_at IS NOT NULL
    AND (p_range_start IS NULL OR s.completed_at >= p_range_start)
    AND (p_range_end IS NULL OR s.completed_at < p_range_end);

  IF p_include_compare AND p_compare_start IS NOT NULL AND p_compare_end IS NOT NULL THEN
    SELECT COALESCE(SUM(oi.quantity), 0)
      INTO v_prev_products
    FROM public.orders o
    JOIN public.order_items oi ON oi.order_id = o.order_id
    JOIN public.shipments s ON s.order_id = o.order_id
    WHERE o.seller_id = v_uid
      AND o.order_status = 'completed'::public.order_status_enum
      AND s.completed_at IS NOT NULL
      AND s.completed_at >= p_compare_start
      AND s.completed_at < p_compare_end;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'bucket_start', agg.bucket_start,
        'earnings_centavos', agg.earnings_centavos
      )
      ORDER BY agg.bucket_start
    ),
    '[]'::jsonb
  )
  INTO v_chart
  FROM (
    SELECT
      date_trunc(v_bucket, e.released_at) AS bucket_start,
      SUM(e.seller_amount_centavos)::bigint AS earnings_centavos
    FROM public.escrow e
    WHERE e.seller_id = v_uid
      AND e.status = 'released'::public.escrow_status_enum
      AND e.released_at IS NOT NULL
      AND (p_range_start IS NULL OR e.released_at >= p_range_start)
      AND (p_range_end IS NULL OR e.released_at < p_range_end)
    GROUP BY 1
  ) agg;

  SELECT COALESCE(
    jsonb_agg(listed.item ORDER BY listed.sort_at DESC),
    '[]'::jsonb
  )
  INTO v_recent
  FROM (
    SELECT jsonb_build_object(
      'order_id', e.order_id,
      'order_number', o.order_number,
      'title', COALESCE((
        SELECT oi.title
        FROM public.order_items oi
        WHERE oi.order_id = e.order_id
        ORDER BY oi.created_at
        LIMIT 1
      ), 'Order'),
      'seller_amount_centavos', e.seller_amount_centavos,
      'released_at', e.released_at
    ) AS item,
    e.released_at AS sort_at
    FROM public.escrow e
    JOIN public.orders o ON o.order_id = e.order_id
    WHERE e.seller_id = v_uid
      AND e.status = 'released'::public.escrow_status_enum
      AND e.released_at IS NOT NULL
      AND (p_range_start IS NULL OR e.released_at >= p_range_start)
      AND (p_range_end IS NULL OR e.released_at < p_range_end)
    ORDER BY e.released_at DESC
    LIMIT 8
  ) listed;

  RETURN jsonb_build_object(
    'success', true,
    'earnings_centavos', v_earnings,
    'previous_earnings_centavos', v_prev_earnings,
    'products_sold', v_products,
    'previous_products_sold', v_prev_products,
    'completed_orders', v_orders,
    'chart', v_chart,
    'recent_sales', v_recent,
    'earnings_basis', 'released_escrow',
    'orders_basis', 'shipment_completed_at'
  );
END;
$$;

COMMENT ON FUNCTION public.seller_analytics_report IS
  'Authenticated seller analytics. Earnings = released escrow seller_amount_centavos; sales counts use completed orders/items.';

REVOKE ALL ON FUNCTION public.seller_analytics_report(
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_analytics_report(
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, text
) TO authenticated;
