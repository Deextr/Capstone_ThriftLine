-- Orders report detail: Type, Seller, Total (₱), Date & Time, Status.

CREATE OR REPLACE FUNCTION public._admin_report_orders_bundle(
  p_from timestamptz,
  p_to timestamptz,
  p_cf timestamptz,
  p_ct timestamptz,
  p_filters jsonb,
  p_limit integer,
  p_offset integer
)
RETURNS TABLE (
  summary jsonb,
  comparison jsonb,
  breakdowns jsonb,
  details jsonb,
  limitations jsonb,
  detail_total bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order_type text := nullif(trim(p_filters->>'order_type'), '');
  v_order_status text := nullif(trim(p_filters->>'order_status'), '');
  v_seller text := nullif(lower(trim(p_filters->>'seller')), '');
  v_total bigint;
  v_completed_shipments bigint;
  v_cancelled bigint;
  v_refunded bigint;
  v_paid_created bigint;
  v_completed_cohort bigint;
  v_comp_rate numeric;
  v_aov numeric;
  v_checkouts bigint;
BEGIN
  SELECT count(*) INTO v_total FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND (v_order_type IS NULL OR o.order_type::text = v_order_type)
    AND (v_order_status IS NULL OR o.order_status::text = v_order_status);

  SELECT count(*) INTO v_completed_shipments
  FROM public.orders o
  INNER JOIN public.shipments s ON s.order_id = o.order_id
  WHERE s.completed_at >= p_from AND s.completed_at < p_to
    AND o.order_status = 'completed'::public.order_status_enum;

  SELECT count(*) INTO v_cancelled
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND o.order_status = 'cancelled'::public.order_status_enum;

  SELECT count(*) INTO v_refunded
  FROM public.escrow e
  WHERE e.refunded_at >= p_from AND e.refunded_at < p_to;

  SELECT count(DISTINCT o.checkout_group_id) INTO v_checkouts
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND o.checkout_group_id IS NOT NULL;

  SELECT avg(o.total_amount) INTO v_aov
  FROM public.orders o
  WHERE EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
      AND p.updated_at >= p_from AND p.updated_at < p_to
  );

  SELECT count(*) INTO v_paid_created
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.order_id = o.order_id AND p.payment_status = 'paid'::public.payment_status_enum
    )
    AND o.order_status IN ('completed'::public.order_status_enum, 'cancelled'::public.order_status_enum);

  SELECT count(*) INTO v_completed_cohort
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND o.order_status = 'completed'::public.order_status_enum
    AND EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.order_id = o.order_id AND p.payment_status = 'paid'::public.payment_status_enum
    );

  IF v_paid_created = 0 THEN
    v_comp_rate := NULL;
  ELSE
    v_comp_rate := round((v_completed_cohort::numeric / v_paid_created::numeric) * 100.0, 1);
  END IF;

  summary := jsonb_build_array(
    public._admin_report_metric('orders_created', 'Orders created', v_total),
    public._admin_report_metric('fixed_price', 'Fixed-price orders',
      (SELECT count(*) FROM public.orders o WHERE o.created_at >= p_from AND o.created_at < p_to
        AND o.order_type = 'fixed_price'::public.order_type_enum)),
    public._admin_report_metric('auction_orders', 'Auction orders',
      (SELECT count(*) FROM public.orders o WHERE o.created_at >= p_from AND o.created_at < p_to
        AND o.order_type = 'auction'::public.order_type_enum)),
    public._admin_report_metric('completed_shipments', 'Completed (shipment date)', v_completed_shipments),
    public._admin_report_metric('cancelled_cohort', 'Cancelled (created in period)', v_cancelled),
    public._admin_report_metric('refunded', 'Refunded orders', v_refunded),
    public._admin_report_metric('aov', 'Average order value (paid)', coalesce(v_aov, 0), 'money'),
    public._admin_report_metric('completion_rate', 'Completion rate (paid cohort)', coalesce(v_comp_rate, 0), 'percent'),
    public._admin_report_metric('checkout_sessions', 'Distinct checkout groups', v_checkouts)
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Orders by status (created in period)',
      'columns', jsonb_build_array('Status', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(s.status, s.cnt)), '[]'::jsonb)
        FROM (
          SELECT o.order_status::text AS status, count(*) AS cnt
          FROM public.orders o
          WHERE o.created_at >= p_from AND o.created_at < p_to
          GROUP BY 1
        ) s
      )
    )
  );

  limitations := jsonb_build_array(
    'Each row is one seller order; multi-shop checkout creates multiple orders.',
    'Completion rate uses paid orders created in the period that are completed or cancelled.',
    'Average order value uses orders with payment updated in the period.'
  );

  SELECT count(*) INTO v_total
  FROM public.orders o
  LEFT JOIN public.users seller ON seller.user_id = o.seller_id
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND (v_order_type IS NULL OR o.order_type::text = v_order_type)
    AND (v_order_status IS NULL OR o.order_status::text = v_order_status)
    AND (v_seller IS NULL OR lower(coalesce(seller.full_name, seller.username, '')) LIKE '%' || v_seller || '%');

  details := jsonb_build_object(
    'columns', jsonb_build_array('Type', 'Seller', 'Total', 'Date & Time', 'Status'),
    'rows', coalesce((
      SELECT jsonb_agg(src.row_data)
      FROM (
        SELECT jsonb_build_array(
          CASE o.order_type::text
            WHEN 'fixed_price' THEN 'Fixed price'
            WHEN 'auction' THEN 'Auction'
            ELSE o.order_type::text
          END,
          left(coalesce(seller.full_name, seller.username, 'Seller'), 40),
          '₱' || to_char(coalesce(o.total_amount, 0), 'FM999,999,990.00'),
          public._admin_report_manila_datetime(o.created_at),
          o.order_status::text
        ) AS row_data
        FROM public.orders o
        LEFT JOIN public.users seller ON seller.user_id = o.seller_id
        WHERE o.created_at >= p_from AND o.created_at < p_to
          AND (v_order_type IS NULL OR o.order_type::text = v_order_type)
          AND (v_order_status IS NULL OR o.order_status::text = v_order_status)
          AND (v_seller IS NULL OR lower(coalesce(seller.full_name, seller.username, '')) LIKE '%' || v_seller || '%')
        ORDER BY o.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ) src
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;
