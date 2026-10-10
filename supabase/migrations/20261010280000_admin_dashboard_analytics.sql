-- Admin dashboard: Manila periods, platform-fee revenue, comparisons, and backlog.
-- Replaces admin_dashboard_snapshot(timestamptz, timestamptz).
-- Idempotent. Do not edit earlier migrations.

DROP FUNCTION IF EXISTS public.admin_dashboard_snapshot(timestamptz, timestamptz);

-- Earliest paid timestamp for one order inside an optional window.
-- Not granted to clients. Used only by admin_dashboard_snapshot.
CREATE OR REPLACE FUNCTION public._admin_dashboard_paid_at(
  p_order_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT min(p.updated_at)
  FROM public.payments p
  WHERE p.order_id = p_order_id
    AND p.payment_status = 'paid'::public.payment_status_enum
    AND (p_from IS NULL OR p.updated_at >= p_from)
    AND (p_to IS NULL OR p.updated_at < p_to);
$$;

-- True when the order has a paid payment in the window and escrow is not refunded.
CREATE OR REPLACE FUNCTION public._admin_dashboard_order_paid(
  p_order_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public._admin_dashboard_paid_at(p_order_id, p_from, p_to) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.escrow e
      WHERE e.order_id = p_order_id
        AND e.status = 'refunded'::public.escrow_status_enum
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_dashboard_snapshot(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_compare_from timestamptz DEFAULT NULL,
  p_compare_to timestamptz DEFAULT NULL,
  p_bucket text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_to timestamptz;
  v_bucket text;
  v_bucket_in text;
  v_compare boolean := false;
  v_user_start timestamptz;
  v_pay_start timestamptz;
  v_history_start timestamptz;
  v_series_from timestamptz;
  v_series_to timestamptz;
  v_origin timestamp;
  v_end_bucket timestamp;
  v_compare_origin timestamp;
  v_step interval;
  v_span_days numeric;
  v_new_users integer := 0;
  v_new_users_prev integer := 0;
  v_completed integer := 0;
  v_completed_prev integer := 0;
  v_paid_orders integer := 0;
  v_paid_orders_prev integer := 0;
  v_revenue numeric := 0;
  v_revenue_prev numeric := 0;
  v_gross numeric := 0;
  v_listings integer := 0;
  v_applications integer := 0;
  v_auction_orders integer := 0;
  v_awaiting integer := 0;
  v_pending_verifications integer := 0;
  v_open_community integer := 0;
  v_open_order integer := 0;
  v_open_looking_for integer := 0;
  v_bidding integer := 0;
  v_payment_review integer := 0;
  v_total_users integer := 0;
  v_period_orders integer := 0;
  v_period_reports integer := 0;
  v_order_categories text[] := ARRAY[
    'seller_not_processing_order',
    'counterfeit_received',
    'item_not_as_described',
    'undisclosed_damage',
    'buyer_delivery_pin_issue',
    'fake_product',
    'counterfeit_item',
    'failure_to_ship'
  ];
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can view the dashboard.'
    );
  END IF;

  v_to := coalesce(p_to, now());
  IF p_from IS NOT NULL AND v_to <= p_from THEN
    v_to := p_from + interval '1 second';
  END IF;

  v_compare := p_from IS NOT NULL
    AND p_compare_from IS NOT NULL
    AND p_compare_to IS NOT NULL
    AND p_compare_to > p_compare_from
    AND (
      EXISTS (SELECT 1 FROM public.users u WHERE u.created_at < p_from)
      OR EXISTS (
        SELECT 1 FROM public.payments p
        WHERE p.payment_status = 'paid'::public.payment_status_enum
          AND p.updated_at < p_from
      )
    );

  SELECT min(u.created_at) INTO v_user_start FROM public.users u;
  SELECT min(p.updated_at) INTO v_pay_start
  FROM public.payments p
  WHERE p.payment_status = 'paid'::public.payment_status_enum;

  v_history_start := CASE
    WHEN v_user_start IS NULL THEN v_pay_start
    WHEN v_pay_start IS NULL THEN v_user_start
    WHEN v_user_start < v_pay_start THEN v_user_start
    ELSE v_pay_start
  END;

  v_bucket_in := lower(btrim(coalesce(p_bucket, '')));
  IF v_bucket_in = 'auto' THEN
    IF v_history_start IS NOT NULL
       AND v_history_start < v_to - interval '36 months' THEN
      v_bucket := 'year';
    ELSE
      v_bucket := 'month';
    END IF;
  ELSIF v_bucket_in IN ('hour', 'day', 'month', 'year') THEN
    v_bucket := v_bucket_in;
  ELSIF p_from IS NULL THEN
    v_bucket := 'month';
  ELSE
    v_span_days := EXTRACT(EPOCH FROM (v_to - p_from)) / 86400.0;
    IF v_span_days <= 1.01 THEN
      v_bucket := 'hour';
    ELSIF v_span_days > 62 THEN
      v_bucket := 'month';
    ELSE
      v_bucket := 'day';
    END IF;
  END IF;

  v_step := CASE v_bucket
    WHEN 'hour' THEN interval '1 hour'
    WHEN 'day' THEN interval '1 day'
    WHEN 'month' THEN interval '1 month'
    ELSE interval '1 year'
  END;

  v_series_to := least(v_to, now());
  IF p_from IS NULL THEN
    v_series_from := v_history_start;
  ELSE
    v_series_from := p_from;
  END IF;

  IF v_series_from IS NOT NULL AND v_series_to > v_series_from THEN
    v_origin := date_trunc(v_bucket, timezone('Asia/Manila', v_series_from));
    v_end_bucket := date_trunc(
      v_bucket,
      timezone('Asia/Manila', v_series_to - interval '1 millisecond')
    );
    IF v_end_bucket < v_origin THEN
      v_end_bucket := v_origin;
    END IF;
    IF v_compare THEN
      v_compare_origin := date_trunc(
        v_bucket,
        timezone('Asia/Manila', p_compare_from)
      );
    END IF;
  END IF;

  SELECT count(*)::int INTO v_new_users
  FROM public.users u
  WHERE (p_from IS NULL OR u.created_at >= p_from)
    AND u.created_at < v_to;

  SELECT count(*)::int INTO v_completed
  FROM public.orders o
  JOIN public.shipments s ON s.order_id = o.order_id
  WHERE o.order_status = 'completed'::public.order_status_enum
    AND s.completed_at IS NOT NULL
    AND (p_from IS NULL OR s.completed_at >= p_from)
    AND s.completed_at < v_to;

  SELECT
    count(*)::int,
    coalesce(sum(o.platform_fee), 0),
    coalesce(sum(o.subtotal + o.shipping_fee), 0)
  INTO v_paid_orders, v_revenue, v_gross
  FROM public.orders o
  WHERE public._admin_dashboard_order_paid(o.order_id, p_from, v_to);

  SELECT count(*)::int INTO v_listings
  FROM public.products p
  WHERE p.status IS DISTINCT FROM 'removed'::public.product_status_enum
    AND (p_from IS NULL OR p.created_at >= p_from)
    AND p.created_at < v_to;

  SELECT count(*)::int INTO v_applications
  FROM public.user_verifications v
  WHERE (p_from IS NULL OR v.submitted_at >= p_from)
    AND v.submitted_at < v_to;

  SELECT count(*)::int INTO v_auction_orders
  FROM public.orders o
  WHERE o.order_type = 'auction'::public.order_type_enum
    AND public._admin_dashboard_order_paid(o.order_id, p_from, v_to);

  SELECT count(*)::int INTO v_awaiting
  FROM public.orders o
  WHERE o.order_status NOT IN (
      'cancelled'::public.order_status_enum,
      'completed'::public.order_status_enum
    )
    AND public._admin_dashboard_order_paid(o.order_id, NULL, now() + interval '1 second')
    AND NOT EXISTS (
      SELECT 1 FROM public.shipments s
      WHERE s.order_id = o.order_id
        AND s.completed_at IS NOT NULL
    );

  SELECT count(*)::int INTO v_pending_verifications
  FROM public.user_verifications v
  WHERE v.verification_status = 'pending'::public.verification_status_enum;

  SELECT count(*)::int INTO v_open_community
  FROM public.reports r
  WHERE r.status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    )
    AND r.order_id IS NULL
    AND NOT (r.category = ANY (v_order_categories));

  SELECT count(*)::int INTO v_open_order
  FROM public.reports r
  WHERE r.status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    )
    AND (
      r.order_id IS NOT NULL
      OR r.category = ANY (v_order_categories)
    );

  SELECT count(*)::int INTO v_open_looking_for
  FROM public.looking_for_reports r
  WHERE r.status IN (
    'under_review'::public.report_status_enum,
    'needs_more_evidence'::public.report_status_enum
  );

  SELECT count(*)::int INTO v_bidding
  FROM public.auction_bidding_sanctions s
  WHERE s.permanently_disabled_at IS NOT NULL
     OR (s.restricted_until IS NOT NULL AND s.restricted_until > now());

  SELECT count(*)::int INTO v_payment_review
  FROM public.orders o
  WHERE o.order_status = 'cancelled'::public.order_status_enum
    AND EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.order_id = o.order_id
        AND p.payment_status = 'paid'::public.payment_status_enum
    );

  SELECT count(*)::int INTO v_total_users FROM public.users u;

  SELECT count(*)::int INTO v_period_orders
  FROM public.orders o
  WHERE (p_from IS NULL OR o.created_at >= p_from)
    AND o.created_at < v_to;

  SELECT count(*)::int INTO v_period_reports
  FROM public.reports r
  WHERE (p_from IS NULL OR r.created_at >= p_from)
    AND r.created_at < v_to;

  IF v_compare THEN
    SELECT count(*)::int INTO v_new_users_prev
    FROM public.users u
    WHERE u.created_at >= p_compare_from
      AND u.created_at < p_compare_to;

    SELECT count(*)::int INTO v_completed_prev
    FROM public.orders o
    JOIN public.shipments s ON s.order_id = o.order_id
    WHERE o.order_status = 'completed'::public.order_status_enum
      AND s.completed_at IS NOT NULL
      AND s.completed_at >= p_compare_from
      AND s.completed_at < p_compare_to;

    SELECT count(*)::int, coalesce(sum(o.platform_fee), 0)
    INTO v_paid_orders_prev, v_revenue_prev
    FROM public.orders o
    WHERE public._admin_dashboard_order_paid(o.order_id, p_compare_from, p_compare_to);
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'schema', 2,
    'generated_at', now(),
    'bucket', v_bucket,
    'comparison_available', v_compare,
    'kpis', jsonb_build_object(
      'new_users', v_new_users,
      'new_users_previous', CASE WHEN v_compare THEN to_jsonb(v_new_users_prev) ELSE NULL END,
      'completed_orders', v_completed,
      'completed_orders_previous', CASE WHEN v_compare THEN to_jsonb(v_completed_prev) ELSE NULL END,
      'platform_revenue', v_revenue,
      'platform_revenue_previous', CASE WHEN v_compare THEN to_jsonb(v_revenue_prev) ELSE NULL END,
      'paid_orders', v_paid_orders,
      'paid_orders_previous', CASE WHEN v_compare THEN to_jsonb(v_paid_orders_prev) ELSE NULL END
    ),
    'activity', jsonb_build_object(
      'new_listings', v_listings,
      'seller_applications', v_applications,
      'paid_auction_orders', v_auction_orders,
      'orders_awaiting_fulfillment', v_awaiting
    ),
    'attention', jsonb_build_object(
      'pending_verifications', v_pending_verifications,
      'open_community_disputes', v_open_community,
      'open_order_disputes', v_open_order,
      'open_looking_for_disputes', v_open_looking_for,
      'active_bidding_restrictions', v_bidding,
      'payment_reviews', v_payment_review
    ),
    'revenue_series', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'at', g.bucket_at,
          'current', COALESCE(cur.amount, 0),
          'previous', CASE
            WHEN v_compare THEN to_jsonb(COALESCE(prev.amount, 0))
            ELSE NULL
          END
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.bucket_local,
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          CASE
            WHEN v_compare THEN v_compare_origin + ((s.ord - 1) * v_step)
            ELSE NULL
          END AS prev_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', fee.paid_at)) AS bucket_local,
          coalesce(sum(fee.platform_fee), 0) AS amount
        FROM (
          SELECT
            o.platform_fee,
            public._admin_dashboard_paid_at(o.order_id, p_from, v_to) AS paid_at
          FROM public.orders o
          WHERE public._admin_dashboard_order_paid(o.order_id, p_from, v_to)
        ) fee
        WHERE fee.paid_at IS NOT NULL
        GROUP BY 1
      ) cur ON cur.bucket_local = g.bucket_local
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', fee.paid_at)) AS bucket_local,
          coalesce(sum(fee.platform_fee), 0) AS amount
        FROM (
          SELECT
            o.platform_fee,
            public._admin_dashboard_paid_at(o.order_id, p_compare_from, p_compare_to) AS paid_at
          FROM public.orders o
          WHERE v_compare
            AND public._admin_dashboard_order_paid(o.order_id, p_compare_from, p_compare_to)
        ) fee
        WHERE fee.paid_at IS NOT NULL
        GROUP BY 1
      ) prev ON prev.bucket_local = g.prev_local
    ), '[]'::jsonb),
    'recent_activity', COALESCE((
      SELECT jsonb_agg(item ORDER BY occurred_at DESC)
      FROM (
        SELECT item, occurred_at
        FROM (
          SELECT
            v.submitted_at AS occurred_at,
            jsonb_build_object(
              'kind', 'verification_submitted',
              'occurred_at', v.submitted_at,
              'title', 'Seller verification submitted',
              'detail', coalesce(nullif(btrim(v.shop_name), ''), 'New shop'),
              'actor', 'member',
              'target_type', 'verification',
              'target_id', v.verification_id::text
            ) AS item
          FROM public.user_verifications v

          UNION ALL

          SELECT
            r.created_at,
            jsonb_build_object(
              'kind', CASE
                WHEN r.order_id IS NOT NULL OR r.category = ANY (v_order_categories)
                  THEN 'order_report_submitted'
                ELSE 'community_report_submitted'
              END,
              'occurred_at', r.created_at,
              'title', CASE
                WHEN r.order_id IS NOT NULL OR r.category = ANY (v_order_categories)
                  THEN 'Order dispute submitted'
                ELSE 'Community dispute submitted'
              END,
              'detail', replace(r.category, '_', ' '),
              'actor', 'member',
              'target_type', 'report',
              'target_id', r.report_id::text
            )
          FROM public.reports r

          UNION ALL

          SELECT
            r.created_at,
            jsonb_build_object(
              'kind', 'looking_for_report_submitted',
              'occurred_at', r.created_at,
              'title', 'Looking For dispute submitted',
              'detail', replace(r.reason, '_', ' '),
              'actor', 'member',
              'target_type', 'looking_for_report',
              'target_id', r.report_id::text
            )
          FROM public.looking_for_reports r

          UNION ALL

          SELECT
            l.created_at,
            jsonb_build_object(
              'kind', l.event_type,
              'occurred_at', l.created_at,
              'title', l.summary,
              'detail', '',
              'actor', 'admin',
              'target_type', coalesce(l.target_type, ''),
              'target_id', coalesce(l.target_id, '')
            )
          FROM public.admin_audit_logs l
          WHERE l.category <> 'authentication'
            AND l.event_type IN (
              'seller_verification_approved',
              'seller_verification_rejected',
              'report_decided',
              'order_report_closed',
              'order_report_evidence_requested',
              'looking_for_report_decided',
              'delivery_dispute_closed'
            )

          UNION ALL

          SELECT
            v.created_at,
            jsonb_build_object(
              'kind', 'bidding_violation',
              'occurred_at', v.created_at,
              'title', 'Bidding violation recorded',
              'detail', 'Auction winner non-payment',
              'actor', 'system',
              'target_type', 'order',
              'target_id', v.order_id::text
            )
          FROM public.auction_bidding_violations v
        ) events
        ORDER BY occurred_at DESC
        LIMIT 12
      ) recent
    ), '[]'::jsonb),
    'counts', jsonb_build_object(
      'total_users', v_total_users,
      'period_users', v_new_users,
      'pending_verifications', v_pending_verifications,
      'period_verifications', v_applications,
      'open_reports', v_open_community + v_open_order,
      'period_reports', v_period_reports,
      'period_orders', v_period_orders,
      'open_disputes', v_open_community + v_open_order + v_open_looking_for,
      'gross_marketplace_sales', v_gross,
      'platform_revenue', v_revenue
    ),
    'registrations', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', u.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.users u
        WHERE (p_from IS NULL OR u.created_at >= p_from)
          AND u.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'orders_by_day', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', o.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.orders o
        WHERE (p_from IS NULL OR o.created_at >= p_from)
          AND o.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'orders_by_status', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      )
      FROM (
        SELECT o.order_status::text AS status, count(*)::int AS cnt
        FROM public.orders o
        WHERE (p_from IS NULL OR o.created_at >= p_from)
          AND o.created_at < v_to
        GROUP BY 1
      ) s
    ), '[]'::jsonb),
    'reports_by_day', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', r.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.reports r
        WHERE (p_from IS NULL OR r.created_at >= p_from)
          AND r.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'reports_by_status', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      )
      FROM (
        SELECT r.status::text AS status, count(*)::int AS cnt
        FROM public.reports r
        WHERE (p_from IS NULL OR r.created_at >= p_from)
          AND r.created_at < v_to
        GROUP BY 1
      ) s
    ), '[]'::jsonb),
    'sales_revenue_series', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'gross', COALESCE(c.gross, 0),
          'platform_revenue', COALESCE(c.platform, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', paid.paid_at)) AS bucket_local,
          sum(o.subtotal + o.shipping_fee) AS gross,
          sum(o.platform_fee) AS platform
        FROM public.orders o
        JOIN LATERAL (
          SELECT public._admin_dashboard_paid_at(o.order_id, p_from, v_to) AS paid_at
        ) paid ON paid.paid_at IS NOT NULL
        WHERE public._admin_dashboard_order_paid(o.order_id, p_from, v_to)
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text) IS
  'Admin dashboard snapshot. Platform revenue is non-refunded paid order fees, not buyer GMV.';

REVOKE ALL ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public._admin_dashboard_paid_at(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_order_paid(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_paid_at(uuid, timestamptz, timestamptz)
  TO CURRENT_USER;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_order_paid(uuid, timestamptz, timestamptz)
  TO CURRENT_USER;
