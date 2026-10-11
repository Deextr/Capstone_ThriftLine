-- Bundled all-reports RPC respects p_detail_limit and p_detail_offset.

CREATE OR REPLACE FUNCTION public.admin_marketplace_report(
  p_category text,
  p_from timestamptz,
  p_to timestamptz,
  p_compare_from timestamptz DEFAULT NULL,
  p_compare_to timestamptz DEFAULT NULL,
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_detail_limit integer DEFAULT 25,
  p_detail_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cat text := lower(trim(COALESCE(p_category, 'overview')));
  v_from timestamptz;
  v_to timestamptz;
  v_cf timestamptz;
  v_ct timestamptz;
  v_limit integer := LEAST(GREATEST(COALESCE(p_detail_limit, 25), 1), 5000);
  v_offset integer := GREATEST(COALESCE(p_detail_offset, 0), 0);
  v_filters jsonb := COALESCE(p_filters, '{}'::jsonb);
  v_active_minutes integer := 15;
  v_super boolean := public.is_super_admin();
  v_result jsonb;
  v_summary jsonb := '[]'::jsonb;
  v_comparison jsonb := '[]'::jsonb;
  v_breakdowns jsonb := '[]'::jsonb;
  v_details jsonb;
  v_limitations jsonb := '[]'::jsonb;
  v_detail_total bigint := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can view marketplace reports.'
    );
  END IF;

  v_from := COALESCE(p_from, date_trunc('day', timezone('Asia/Manila', now())) AT TIME ZONE 'Asia/Manila');
  v_to := COALESCE(p_to, v_from + interval '1 day');
  IF v_to <= v_from THEN
    v_to := v_from + interval '1 day';
  END IF;
  v_cf := p_compare_from;
  v_ct := p_compare_to;

  IF v_cat NOT IN (
    'overview', 'users', 'orders', 'payments', 'auctions',
    'disputes', 'verifications', 'security', 'all'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid report category.');
  END IF;

  IF v_cat = 'all' THEN
    v_result := jsonb_build_object(
      'success', true,
      'category', v_cat,
      'generated_at', now(),
      'range_from', v_from,
      'range_to', v_to,
      'compare_from', v_cf,
      'compare_to', v_ct,
      'overview', jsonb_build_object(
        'summary', public._admin_report_overview_summary(v_from, v_to),
        'comparison', CASE
          WHEN v_cf IS NOT NULL AND v_ct IS NOT NULL AND v_ct > v_cf
            THEN public._admin_report_overview_comparison(v_from, v_to, v_cf, v_ct)
          ELSE '[]'::jsonb
        END
      ),
      'users', (SELECT row_to_json(u)::jsonb FROM public._admin_report_users_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset, v_super
      ) u),
      'orders', (SELECT row_to_json(o)::jsonb FROM public._admin_report_orders_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
      ) o),
      'payments', (SELECT row_to_json(p)::jsonb FROM public._admin_report_payments_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
      ) p),
      'auctions', (SELECT row_to_json(a)::jsonb FROM public._admin_report_auctions_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
      ) a),
      'disputes', (SELECT row_to_json(d)::jsonb FROM public._admin_report_disputes_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
      ) d),
      'verifications', (SELECT row_to_json(v)::jsonb FROM public._admin_report_verifications_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
      ) v),
      'security', (SELECT row_to_json(s)::jsonb FROM public._admin_report_security_bundle(
        v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset, v_super
      ) s),
      'limitations', v_limitations
    );
    RETURN v_result;
  END IF;

  IF v_cat = 'overview' THEN
    v_summary := public._admin_report_overview_summary(v_from, v_to);
    v_limitations := jsonb_build_array(
      'Currently active users is a live snapshot (last 15 minutes), not a historical period count.',
      'Cancelled orders counts orders created in the period that are currently cancelled; there is no cancelled_at timestamp.',
      'Gross order value and platform fees use payment updated_at for paid, non-refunded orders.',
      'New disputes exclude delivery_disputes; resolved counts use resolved_at on reports and looking_for_reports.'
    );
    IF v_cf IS NOT NULL AND v_ct IS NOT NULL AND v_ct > v_cf THEN
      v_comparison := public._admin_report_overview_comparison(v_from, v_to, v_cf, v_ct);
    END IF;
    v_breakdowns := jsonb_build_array(
      jsonb_build_object(
        'title', 'Overview metrics',
        'columns', jsonb_build_array('Metric', 'Value'),
        'rows', (
          SELECT coalesce(jsonb_agg(jsonb_build_array(s->>'label', s->>'display')), '[]'::jsonb)
          FROM jsonb_array_elements(v_summary) s
        )
      )
    );
    v_details := jsonb_build_object(
      'columns', jsonb_build_array('Metric', 'Value', 'Notes'),
      'rows', '[]'::jsonb,
      'total', 0,
      'truncated', false
    );
    v_detail_total := 0;
  ELSIF v_cat = 'users' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_users_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset, v_super
    ) s;
  ELSIF v_cat = 'orders' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_orders_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
    ) s;
  ELSIF v_cat = 'payments' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_payments_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
    ) s;
  ELSIF v_cat = 'auctions' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_auctions_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
    ) s;
  ELSIF v_cat = 'disputes' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_disputes_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
    ) s;
  ELSIF v_cat = 'verifications' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_verifications_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset
    ) s;
  ELSIF v_cat = 'security' THEN
    SELECT s.summary, s.comparison, s.breakdowns, s.details, s.limitations, s.detail_total
    INTO v_summary, v_comparison, v_breakdowns, v_details, v_limitations, v_detail_total
    FROM public._admin_report_security_bundle(
      v_from, v_to, v_cf, v_ct, v_filters, v_limit, v_offset, v_super
    ) s;
  END IF;

  IF v_details IS NULL THEN
    v_details := jsonb_build_object(
      'columns', '[]'::jsonb,
      'rows', '[]'::jsonb,
      'total', 0,
      'truncated', false
    );
  END IF;

  v_result := jsonb_build_object(
    'success', true,
    'category', v_cat,
    'generated_at', now(),
    'range_from', v_from,
    'range_to', v_to,
    'compare_from', v_cf,
    'compare_to', v_ct,
    'summary', v_summary,
    'comparison', v_comparison,
    'breakdowns', v_breakdowns,
    'details', v_details,
    'detail_total', v_detail_total,
    'limitations', v_limitations
  );
  RETURN v_result;
END;
$$;

-- Overview summary metrics (jsonb array of objects).
CREATE OR REPLACE FUNCTION public._admin_report_metric(
  p_key text,
  p_label text,
  p_value numeric,
  p_kind text DEFAULT 'count',
  p_snapshot boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'key', p_key,
    'label', p_label,
    'value', p_value,
    'kind', p_kind,
    'snapshot', p_snapshot,
    'display', CASE
      WHEN p_kind = 'money' THEN to_char(p_value, 'FM999,999,990.00')
      WHEN p_kind = 'percent' THEN to_char(p_value, 'FM990.0') || '%'
      ELSE to_char(p_value, 'FM999,999,990')
    END
  );
$$;

CREATE OR REPLACE FUNCTION public._admin_report_overview_summary(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_active_minutes integer := 15;
  v_new_regs bigint;
  v_active_now bigint;
  v_sellers_approved bigint;
  v_listings bigint;
  v_completed bigint;
  v_cancelled bigint;
  v_gov numeric;
  v_platform numeric;
  v_refunds numeric;
  v_new_disp bigint;
  v_resolved_disp bigint;
BEGIN
  SELECT count(*) INTO v_new_regs
  FROM public.users u
  WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
    AND u.created_at >= p_from AND u.created_at < p_to;

  SELECT count(*) INTO v_active_now
  FROM public.users u
  WHERE u.account_status = 'active'::public.account_status_enum
    AND u.last_active_at IS NOT NULL
    AND u.last_active_at >= now() - make_interval(mins => v_active_minutes);

  SELECT count(*) INTO v_sellers_approved
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.verification_status = 'approved'::public.verification_status_enum
    AND v.reviewed_at >= p_from AND v.reviewed_at < p_to;

  SELECT count(*) INTO v_listings
  FROM public.products p
  WHERE p.created_at >= p_from AND p.created_at < p_to;

  SELECT count(*) INTO v_completed
  FROM public.orders o
  INNER JOIN public.shipments s ON s.order_id = o.order_id
  WHERE o.order_status = 'completed'::public.order_status_enum
    AND s.completed_at >= p_from AND s.completed_at < p_to;

  SELECT count(*) INTO v_cancelled
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND o.order_status = 'cancelled'::public.order_status_enum;

  SELECT coalesce(sum(o.subtotal + o.shipping_fee), 0),
         coalesce(sum(o.platform_fee), 0)
  INTO v_gov, v_platform
  FROM public.orders o
  WHERE EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
      AND p.updated_at >= p_from AND p.updated_at < p_to
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.escrow e
    WHERE e.order_id = o.order_id
      AND e.status = 'refunded'::public.escrow_status_enum
  );

  SELECT coalesce(sum(e.amount_centavos), 0) / 100.0 INTO v_refunds
  FROM public.escrow e
  WHERE e.status = 'refunded'::public.escrow_status_enum
    AND e.refunded_at >= p_from AND e.refunded_at < p_to;

  SELECT
    (SELECT count(*) FROM public.reports r
     WHERE r.created_at >= p_from AND r.created_at < p_to)
    + (SELECT count(*) FROM public.looking_for_reports lfr
       WHERE lfr.created_at >= p_from AND lfr.created_at < p_to)
  INTO v_new_disp;

  SELECT
    (SELECT count(*) FROM public.reports r
     WHERE r.status = 'resolved'::public.report_status_enum
       AND r.resolved_at >= p_from AND r.resolved_at < p_to)
    + (SELECT count(*) FROM public.looking_for_reports lfr
       WHERE lfr.status = 'resolved'::public.report_status_enum
         AND lfr.resolved_at >= p_from AND lfr.resolved_at < p_to)
  INTO v_resolved_disp;

  RETURN jsonb_build_array(
    public._admin_report_metric('new_registrations', 'New registrations', v_new_regs),
    public._admin_report_metric('active_now', 'Currently active users', v_active_now, 'count', true),
    public._admin_report_metric('sellers_approved', 'Sellers approved', v_sellers_approved),
    public._admin_report_metric('new_listings', 'Listings created', v_listings),
    public._admin_report_metric('completed_orders', 'Completed orders', v_completed),
    public._admin_report_metric('cancelled_orders', 'Cancelled orders (created in period)', v_cancelled),
    public._admin_report_metric('gross_order_value', 'Gross order value', v_gov, 'money'),
    public._admin_report_metric('platform_fee_revenue', 'Platform fee revenue', v_platform, 'money'),
    public._admin_report_metric('refund_amount', 'Confirmed refunds', v_refunds, 'money'),
    public._admin_report_metric('new_disputes', 'New disputes', v_new_disp),
    public._admin_report_metric('resolved_disputes', 'Resolved disputes', v_resolved_disp)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_overview_comparison(
  p_from timestamptz,
  p_to timestamptz,
  p_cf timestamptz,
  p_ct timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cur jsonb;
  v_prev jsonb;
  v_row jsonb;
  v_out jsonb := '[]'::jsonb;
  v_key text;
  v_c numeric;
  v_p numeric;
  v_chg numeric;
  v_elem jsonb;
BEGIN
  v_cur := public._admin_report_overview_summary(p_from, p_to);
  v_prev := public._admin_report_overview_summary(p_cf, p_ct);
  FOR v_elem IN SELECT * FROM jsonb_array_elements(v_cur)
  LOOP
    v_key := v_elem->>'key';
    IF coalesce((v_elem->>'snapshot')::boolean, false) THEN
      CONTINUE;
    END IF;
    v_c := (v_elem->>'value')::numeric;
    SELECT (p->>'value')::numeric INTO v_p
    FROM jsonb_array_elements(v_prev) p
    WHERE p->>'key' = v_key
    LIMIT 1;
    IF v_p IS NULL OR v_p = 0 THEN
      v_chg := NULL;
    ELSE
      v_chg := round(((v_c - v_p) / v_p) * 100.0, 1);
    END IF;
    v_out := v_out || jsonb_build_object(
      'key', v_key,
      'label', v_elem->>'label',
      'current', v_c,
      'previous', coalesce(v_p, 0),
      'change_pct', v_chg
    );
  END LOOP;
  RETURN v_out;
END;
$$;

-- Bundle return type implemented as composite-like via json in plpgsql functions.
-- Users bundle
CREATE OR REPLACE FUNCTION public._admin_report_users_bundle(
  p_from timestamptz,
  p_to timestamptz,
  p_cf timestamptz,
  p_ct timestamptz,
  p_filters jsonb,
  p_limit integer,
  p_offset integer,
  p_super boolean
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
  v_summary jsonb;
  v_comparison jsonb := '[]'::jsonb;
  v_breakdowns jsonb;
  v_details jsonb;
  v_limitations jsonb;
  v_total bigint;
  v_account_type text := nullif(trim(p_filters->>'account_type'), '');
  v_account_status text := nullif(trim(p_filters->>'account_status'), '');
BEGIN
  SELECT jsonb_build_array(
    public._admin_report_metric('total_marketplace', 'Total marketplace users',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)), 'count', true),
    public._admin_report_metric('buyer_only', 'Buyer only (current)',
      (SELECT count(*) FROM public.users u
       LEFT JOIN public.seller_profiles sp ON sp.user_id = u.user_id
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false))), 'count', true),
    public._admin_report_metric('buyer_and_seller', 'Buyer and seller (current)',
      (SELECT count(*) FROM public.users u
       LEFT JOIN public.seller_profiles sp ON sp.user_id = u.user_id
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false))), 'count', true),
    public._admin_report_metric('new_registrations', 'New registrations',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.created_at >= p_from AND u.created_at < p_to)),
    public._admin_report_metric('active_accounts', 'Active accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'active'::public.account_status_enum), 'count', true),
    public._admin_report_metric('disabled_accounts', 'Disabled accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'suspended'::public.account_status_enum), 'count', true),
    public._admin_report_metric('banned_accounts', 'Banned accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'banned'::public.account_status_enum), 'count', true),
    public._admin_report_metric('sellers_approved_period', 'Sellers approved in period',
      (SELECT count(*) FROM public.user_verifications v
       WHERE v.application_type = 'seller'
         AND v.verification_status = 'approved'::public.verification_status_enum
         AND v.reviewed_at >= p_from AND v.reviewed_at < p_to))
  ) INTO v_summary;

  IF p_cf IS NOT NULL AND p_ct IS NOT NULL AND p_ct > p_cf THEN
    v_comparison := jsonb_build_array(
      jsonb_build_object(
        'key', 'new_registrations',
        'label', 'New registrations',
        'current', (SELECT count(*) FROM public.users u
          WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
            AND u.created_at >= p_from AND u.created_at < p_to),
        'previous', (SELECT count(*) FROM public.users u
          WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
            AND u.created_at >= p_cf AND u.created_at < p_ct),
        'change_pct', NULL
      )
    );
    -- fill change_pct
    SELECT jsonb_agg(
      jsonb_set(
        elem,
        '{change_pct}',
        CASE
          WHEN (elem->>'previous')::numeric = 0 THEN 'null'::jsonb
          ELSE to_jsonb(round(
            (((elem->>'current')::numeric - (elem->>'previous')::numeric)
              / (elem->>'previous')::numeric) * 100.0, 1))
        END
      )
    ) INTO v_comparison
    FROM jsonb_array_elements(v_comparison) elem;
  END IF;

  v_breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Account status (marketplace, current)',
      'columns', jsonb_build_array('Status', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(u.account_status::text, u.cnt)), '[]'::jsonb)
        FROM (
          SELECT account_status, count(*)::bigint AS cnt
          FROM public.users
          WHERE role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
          GROUP BY 1
        ) u
      )
    )
  );

  IF p_super THEN
    v_summary := v_summary || jsonb_build_array(
      public._admin_report_metric('restrictions_applied', 'Account disables in period',
        (SELECT count(*) FROM public.admin_audit_logs l
         WHERE l.event_type = 'marketplace_account_disabled'
           AND l.created_at >= p_from AND l.created_at < p_to))
    );
  END IF;

  v_limitations := jsonb_build_array(
    'ThriftLine has no seller-only accounts; users are buyer-only or buyer+seller.',
    'Seller capability: role=seller OR seller_profiles.is_approved.',
    'Admin and super_admin accounts are excluded from marketplace user counts.'
  );

  SELECT count(*) INTO v_total
  FROM public.users u
  LEFT JOIN public.seller_profiles sp ON sp.user_id = u.user_id
  WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
    AND u.created_at >= p_from AND u.created_at < p_to
    AND (v_account_status IS NULL OR u.account_status::text = v_account_status)
    AND (
      v_account_type IS NULL
      OR (v_account_type = 'buyer_only' AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
      OR (v_account_type = 'buyer_seller' AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
    );

  SELECT jsonb_build_object(
    'columns', jsonb_build_array('Registered', 'Account type', 'Status'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        to_char(u.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        CASE WHEN u.role = 'seller'::public.user_role_enum OR u.is_approved
          THEN 'Buyer + Seller' ELSE 'Buyer only' END,
        u.account_status::text
      ))
      FROM (
        SELECT u.user_id, u.created_at, u.role, u.account_status, coalesce(sp.is_approved, false) AS is_approved
        FROM public.users u
        LEFT JOIN public.seller_profiles sp ON sp.user_id = u.user_id
        WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
          AND u.created_at >= p_from AND u.created_at < p_to
          AND (v_account_status IS NULL OR u.account_status::text = v_account_status)
          AND (
            v_account_type IS NULL
            OR (v_account_type = 'buyer_only' AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
            OR (v_account_type = 'buyer_seller' AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
          )
        ORDER BY u.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ) u
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  ) INTO v_details;

  summary := v_summary;
  comparison := v_comparison;
  breakdowns := v_breakdowns;
  details := v_details;
  limitations := v_limitations;
  detail_total := v_total;
  RETURN NEXT;
END;
$$;

-- Orders bundle (abbreviated helpers inline)
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
  v_completed bigint;
  v_cancelled bigint;
  v_refunded bigint;
  v_paid_created bigint;
  v_comp_rate numeric;
  v_aov numeric;
  v_checkouts bigint;
BEGIN
  SELECT count(*) INTO v_total FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND (v_order_type IS NULL OR o.order_type::text = v_order_type)
    AND (v_order_status IS NULL OR o.order_status::text = v_order_status);

  SELECT count(*) INTO v_completed
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

  SELECT count(*) INTO v_completed FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to
    AND o.order_status = 'completed'::public.order_status_enum
    AND EXISTS (SELECT 1 FROM public.payments p WHERE p.order_id = o.order_id AND p.payment_status = 'paid'::public.payment_status_enum);

  IF v_paid_created = 0 THEN
    v_comp_rate := NULL;
  ELSE
    v_comp_rate := round((v_completed::numeric / v_paid_created::numeric) * 100.0, 1);
  END IF;

  summary := jsonb_build_array(
    public._admin_report_metric('orders_created', 'Orders created', v_total),
    public._admin_report_metric('fixed_price', 'Fixed-price orders',
      (SELECT count(*) FROM public.orders o WHERE o.created_at >= p_from AND o.created_at < p_to
        AND o.order_type = 'fixed_price'::public.order_type_enum)),
    public._admin_report_metric('auction_orders', 'Auction orders',
      (SELECT count(*) FROM public.orders o WHERE o.created_at >= p_from AND o.created_at < p_to
        AND o.order_type = 'auction'::public.order_type_enum)),
    public._admin_report_metric('completed_shipments', 'Completed (shipment date)', v_completed),
    public._admin_report_metric('cancelled_cohort', 'Cancelled (created in period)', v_cancelled),
    public._admin_report_metric('refunded', 'Refunded orders', v_refunded),
    public._admin_report_metric('aov', 'Average order value (paid)', coalesce(v_aov, 0), 'money'),
    public._admin_report_metric('completion_rate', 'Completion rate (paid cohort)', coalesce(v_comp_rate, 0), 'percent'),
    public._admin_report_metric('checkout_sessions', 'Distinct checkout groups', v_checkouts)
  );

  comparison := '[]'::jsonb;
  IF p_cf IS NOT NULL AND p_ct IS NOT NULL THEN
    comparison := jsonb_build_array(
      jsonb_build_object(
        'key', 'orders_created',
        'label', 'Orders created',
        'current', v_total,
        'previous', (SELECT count(*) FROM public.orders o
          WHERE o.created_at >= p_cf AND o.created_at < p_ct),
        'change_pct', NULL
      )
    );
  END IF;

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
    'columns', jsonb_build_array('Created', 'Type', 'Status', 'Total', 'Seller'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        to_char(o.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        o.order_type::text,
        o.order_status::text,
        o.total_amount,
        left(coalesce(seller.full_name, seller.username, 'Seller'), 40)
      ))
      FROM public.orders o
      LEFT JOIN public.users seller ON seller.user_id = o.seller_id
      WHERE o.created_at >= p_from AND o.created_at < p_to
        AND (v_order_type IS NULL OR o.order_type::text = v_order_type)
        AND (v_order_status IS NULL OR o.order_status::text = v_order_status)
        AND (v_seller IS NULL OR lower(coalesce(seller.full_name, seller.username, '')) LIKE '%' || v_seller || '%')
      ORDER BY o.created_at DESC
      LIMIT p_limit OFFSET p_offset
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_payments_bundle(
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
  v_ps text := nullif(trim(p_filters->>'payment_status'), '');
  v_total bigint;
  v_gpv numeric;
  v_gov numeric;
  v_fees_collected numeric;
  v_fees_assessed numeric;
  v_pending numeric;
  v_refund_amt numeric;
  v_failed bigint;
  v_net numeric;
BEGIN
  SELECT count(*), coalesce(sum(p.amount_centavos), 0) / 100.0
  INTO v_total, v_gpv
  FROM public.payments p
  WHERE p.payment_status = 'paid'::public.payment_status_enum
    AND p.updated_at >= p_from AND p.updated_at < p_to;

  SELECT coalesce(sum(o.subtotal + o.shipping_fee), 0),
         coalesce(sum(o.platform_fee), 0)
  INTO v_gov, v_fees_collected
  FROM public.orders o
  WHERE EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
      AND p.updated_at >= p_from AND p.updated_at < p_to
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.escrow e
    WHERE e.order_id = o.order_id AND e.status = 'refunded'::public.escrow_status_enum
  );

  SELECT coalesce(sum(o.platform_fee), 0) INTO v_fees_assessed
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to;

  SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 INTO v_pending
  FROM public.escrow e
  WHERE e.status IN ('held'::public.escrow_status_enum, 'disputed'::public.escrow_status_enum);

  SELECT coalesce(sum(e.amount_centavos), 0) / 100.0 INTO v_refund_amt
  FROM public.escrow e
  WHERE e.status = 'refunded'::public.escrow_status_enum
    AND e.refunded_at >= p_from AND e.refunded_at < p_to;

  SELECT count(*) INTO v_failed
  FROM public.payments p
  WHERE p.payment_status = 'failed'::public.payment_status_enum
    AND p.updated_at >= p_from AND p.updated_at < p_to;

  v_net := v_fees_collected;

  summary := jsonb_build_array(
    public._admin_report_metric('successful_payments', 'Successful order payments', v_total),
    public._admin_report_metric('gross_payment_volume', 'Gross payment volume', v_gpv, 'money'),
    public._admin_report_metric('gross_order_value', 'Gross order value', v_gov, 'money'),
    public._admin_report_metric('platform_fees_collected', 'Platform fees collected', v_fees_collected, 'money'),
    public._admin_report_metric('platform_fees_assessed', 'Platform fees assessed (orders created)', v_fees_assessed, 'money'),
    public._admin_report_metric('seller_allocations', 'Seller allocations (held_at in period)',
      (SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 FROM public.escrow e
       WHERE e.held_at >= p_from AND e.held_at < p_to), 'money'),
    public._admin_report_metric('released_earnings', 'Released seller earnings',
      (SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 FROM public.escrow e
       WHERE e.status = 'released'::public.escrow_status_enum
         AND e.released_at >= p_from AND e.released_at < p_to), 'money'),
    public._admin_report_metric('pending_escrow', 'Pending escrow (snapshot)', v_pending, 'money', true),
    public._admin_report_metric('refunds', 'Confirmed refunds', v_refund_amt, 'money'),
    public._admin_report_metric('failed_payments', 'Failed payments', v_failed),
    public._admin_report_metric('net_platform_revenue', 'Net platform revenue (fees, non-refunded)', v_net, 'money')
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Payment status (updated in period)',
      'columns', jsonb_build_array('Status', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(p.payment_status::text, p.cnt)), '[]'::jsonb)
        FROM (
          SELECT payment_status, count(*) AS cnt
          FROM public.payments
          WHERE updated_at >= p_from AND updated_at < p_to
          GROUP BY 1
        ) p
      )
    )
  );

  limitations := jsonb_build_array(
    'Successful payments dated by payments.updated_at (no paid_at column).',
    'Gross payment volume sums all paid payment rows; multi-shop checkout has one row per seller.',
    'Buyer payment totals are not platform revenue. GCash disbursements are not tracked beyond payout requests.',
    'Expired PayMongo sessions are stored as failed payments.'
  );

  SELECT count(*) INTO v_total
  FROM public.payments p
  WHERE p.updated_at >= p_from AND p.updated_at < p_to
    AND (v_ps IS NULL OR p.payment_status::text = v_ps);

  details := jsonb_build_object(
    'columns', jsonb_build_array('Updated', 'Status', 'Amount', 'Order'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        to_char(p.updated_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        p.payment_status::text,
        round(p.amount_centavos / 100.0, 2),
        left(p.order_id::text, 8)
      ))
      FROM public.payments p
      WHERE p.updated_at >= p_from AND p.updated_at < p_to
        AND (v_ps IS NULL OR p.payment_status::text = v_ps)
      ORDER BY p.updated_at DESC
      LIMIT p_limit OFFSET p_offset
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_auctions_bundle(
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
  v_outcome text := nullif(trim(p_filters->>'auction_outcome'), '');
  v_total bigint;
BEGIN
  summary := jsonb_build_array(
    public._admin_report_metric('created', 'Auctions created',
      (SELECT count(*) FROM public.auctions a WHERE a.created_at >= p_from AND a.created_at < p_to)),
    public._admin_report_metric('ended', 'Auctions ended',
      (SELECT count(*) FROM public.auctions a
       WHERE a.status = 'ended'::public.auction_status_enum
         AND a.ends_at >= p_from AND a.ends_at < p_to)),
    public._admin_report_metric('cancelled', 'Auctions cancelled (approx.)',
      (SELECT count(*) FROM public.auctions a
       WHERE a.status = 'cancelled'::public.auction_status_enum
         AND a.updated_at >= p_from AND a.updated_at < p_to)),
    public._admin_report_metric('ended_with_winner', 'Ended with winner',
      (SELECT count(*) FROM public.auctions a
       WHERE a.status = 'ended'::public.auction_status_enum
         AND a.ends_at >= p_from AND a.ends_at < p_to
         AND a.winner_id IS NOT NULL)),
    public._admin_report_metric('ended_no_bids', 'Ended without winner',
      (SELECT count(*) FROM public.auctions a
       WHERE a.status = 'ended'::public.auction_status_enum
         AND a.ends_at >= p_from AND a.ends_at < p_to
         AND a.winner_id IS NULL)),
    public._admin_report_metric('winning_paid', 'Winning auctions paid',
      (SELECT count(*) FROM public.auctions a
       INNER JOIN public.orders o ON o.auction_id = a.auction_id
       INNER JOIN public.payments p ON p.order_id = o.order_id AND p.payment_status = 'paid'::public.payment_status_enum
       WHERE a.ends_at >= p_from AND a.ends_at < p_to AND a.winner_id IS NOT NULL)),
    public._admin_report_metric('winning_unpaid', 'Winning auctions unpaid',
      (SELECT count(*) FROM public.auctions a
       INNER JOIN public.orders o ON o.auction_id = a.auction_id
       LEFT JOIN public.payments p ON p.order_id = o.order_id AND p.payment_status = 'paid'::public.payment_status_enum
       WHERE a.ends_at >= p_from AND a.ends_at < p_to AND a.winner_id IS NOT NULL AND p.payment_id IS NULL)),
    public._admin_report_metric('relisted', 'Relists (approx.)',
      (SELECT count(*) FROM public.auctions a
       WHERE a.bid_round > 1 AND a.updated_at >= p_from AND a.updated_at < p_to)),
    public._admin_report_metric('bids', 'Bids placed',
      (SELECT count(*) FROM public.bids b WHERE b.created_at >= p_from AND b.created_at < p_to)),
    public._admin_report_metric('violations', 'Bidding violations',
      (SELECT count(*) FROM public.auction_bidding_violations v
       WHERE v.created_at >= p_from AND v.created_at < p_to))
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Auction status (created in period)',
      'columns', jsonb_build_array('Status', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(a.status::text, a.cnt)), '[]'::jsonb)
        FROM (
          SELECT status, count(*) AS cnt FROM public.auctions
          WHERE created_at >= p_from AND created_at < p_to GROUP BY 1
        ) a
      )
    )
  );

  limitations := jsonb_build_array(
    'A selected winner is not counted as a sale until payment succeeds.',
    'Cancelled and relist dates use updated_at; no dedicated cancelled_at or relisted_at.',
    'Auction payment window is 12 hours from order payment_due_at.'
  );

  SELECT count(*) INTO v_total FROM public.auctions a
  WHERE a.created_at >= p_from AND a.created_at < p_to;

  details := jsonb_build_object(
    'columns', jsonb_build_array('Created', 'Status', 'Ends', 'Winner', 'Bid round'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        to_char(a.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        a.status::text,
        to_char(a.ends_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        CASE WHEN a.winner_id IS NULL THEN 'None' ELSE 'Yes' END,
        a.bid_round
      ))
      FROM public.auctions a
      WHERE a.created_at >= p_from AND a.created_at < p_to
        AND (
          v_outcome IS NULL
          OR (v_outcome = 'with_winner' AND a.winner_id IS NOT NULL)
          OR (v_outcome = 'no_winner' AND a.winner_id IS NULL AND a.status = 'ended'::public.auction_status_enum)
        )
      ORDER BY a.created_at DESC
      LIMIT p_limit OFFSET p_offset
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_disputes_bundle(
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
  v_type text := nullif(trim(p_filters->>'dispute_type'), '');
  v_status text := nullif(trim(p_filters->>'dispute_status'), '');
  v_total bigint;
  v_avg_hours numeric;
BEGIN
  SELECT avg(extract(epoch FROM (r.resolved_at - r.created_at)) / 3600.0) INTO v_avg_hours
  FROM public.reports r
  WHERE r.resolved_at >= p_from AND r.resolved_at < p_to
    AND r.status = 'resolved'::public.report_status_enum;

  summary := jsonb_build_array(
    public._admin_report_metric('submitted', 'Disputes submitted',
      (SELECT count(*) FROM public.reports r WHERE r.created_at >= p_from AND r.created_at < p_to)
      + (SELECT count(*) FROM public.looking_for_reports l WHERE l.created_at >= p_from AND l.created_at < p_to)),
    public._admin_report_metric('resolved', 'Resolved in period',
      (SELECT count(*) FROM public.reports r
       WHERE r.resolved_at >= p_from AND r.resolved_at < p_to AND r.status = 'resolved'::public.report_status_enum)
      + (SELECT count(*) FROM public.looking_for_reports l
         WHERE l.resolved_at >= p_from AND l.resolved_at < p_to AND l.status = 'resolved'::public.report_status_enum)),
    public._admin_report_metric('dismissed', 'Dismissed in period',
      (SELECT count(*) FROM public.reports r
       WHERE r.resolved_at >= p_from AND r.resolved_at < p_to AND r.status = 'dismissed'::public.report_status_enum)
      + (SELECT count(*) FROM public.looking_for_reports l
         WHERE l.resolved_at >= p_from AND l.resolved_at < p_to AND l.status = 'dismissed'::public.report_status_enum)),
    public._admin_report_metric('pending_snapshot', 'Under review (snapshot)',
      (SELECT count(*) FROM public.reports r WHERE r.status = 'under_review'::public.report_status_enum)
      + (SELECT count(*) FROM public.looking_for_reports l WHERE l.status = 'under_review'::public.report_status_enum),
      'count', true),
    public._admin_report_metric('needs_evidence', 'Needs evidence (snapshot)',
      (SELECT count(*) FROM public.reports r WHERE r.status = 'needs_more_evidence'::public.report_status_enum),
      'count', true),
    public._admin_report_metric('avg_resolution_hours', 'Avg resolution time (hours)', coalesce(v_avg_hours, 0), 'count'),
    public._admin_report_metric('refund_outcomes', 'Order disputes → refund buyer',
      (SELECT count(*) FROM public.reports r
       WHERE r.order_id IS NOT NULL AND r.resolution_financial = 'refund_buyer'
         AND r.resolved_at >= p_from AND r.resolved_at < p_to)),
    public._admin_report_metric('release_outcomes', 'Order disputes → release seller',
      (SELECT count(*) FROM public.reports r
       WHERE r.order_id IS NOT NULL AND r.resolution_financial = 'release_seller'
         AND r.resolved_at >= p_from AND r.resolved_at < p_to))
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Reports by type (submitted in period)',
      'columns', jsonb_build_array('Type', 'Count'),
      'rows', jsonb_build_array(
        jsonb_build_array('Community', (SELECT count(*) FROM public.reports r
          WHERE r.order_id IS NULL AND r.created_at >= p_from AND r.created_at < p_to)),
        jsonb_build_array('Order', (SELECT count(*) FROM public.reports r
          WHERE r.order_id IS NOT NULL AND r.created_at >= p_from AND r.created_at < p_to)),
        jsonb_build_array('Looking For', (SELECT count(*) FROM public.looking_for_reports l
          WHERE l.created_at >= p_from AND l.created_at < p_to))
      )
    )
  );

  limitations := jsonb_build_array(
    'Delivery disputes are tracked separately and not included in submitted totals.',
    'No admin review SLA is defined; overdue review counts are omitted.',
    'Evidence files and private details are excluded from detail rows.'
  );

  WITH combined AS (
    SELECT 'community'::text AS typ, r.report_id::text AS id, r.status::text AS st,
           r.reason, r.created_at, r.resolved_at
    FROM public.reports r
    WHERE r.order_id IS NULL AND r.created_at >= p_from AND r.created_at < p_to
    UNION ALL
    SELECT 'order', r.report_id::text, r.status::text, r.reason, r.created_at, r.resolved_at
    FROM public.reports r
    WHERE r.order_id IS NOT NULL AND r.created_at >= p_from AND r.created_at < p_to
    UNION ALL
    SELECT 'looking_for', l.report_id::text, l.status::text, l.reason, l.created_at, l.resolved_at
    FROM public.looking_for_reports l
    WHERE l.created_at >= p_from AND l.created_at < p_to
  )
  SELECT count(*) INTO v_total FROM combined c
  WHERE (v_type IS NULL OR c.typ = v_type)
    AND (v_status IS NULL OR c.st = v_status);

  details := jsonb_build_object(
    'columns', jsonb_build_array('Type', 'Status', 'Reason', 'Submitted', 'Resolved'),
    'rows', coalesce((
      WITH combined AS (
        SELECT 'community'::text AS typ, r.status::text AS st, r.reason,
               r.created_at, r.resolved_at
        FROM public.reports r
        WHERE r.order_id IS NULL AND r.created_at >= p_from AND r.created_at < p_to
        UNION ALL
        SELECT 'order', r.status::text, r.reason, r.created_at, r.resolved_at
        FROM public.reports r
        WHERE r.order_id IS NOT NULL AND r.created_at >= p_from AND r.created_at < p_to
        UNION ALL
        SELECT 'looking_for', l.status::text, l.reason, l.created_at, l.resolved_at
        FROM public.looking_for_reports l
        WHERE l.created_at >= p_from AND l.created_at < p_to
      )
      SELECT jsonb_agg(jsonb_build_array(
        c.typ, c.st, left(c.reason, 60),
        to_char(c.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        coalesce(to_char(c.resolved_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'), '—')
      ))
      FROM (
        SELECT * FROM combined
        WHERE (v_type IS NULL OR typ = v_type)
          AND (v_status IS NULL OR st = v_status)
        ORDER BY created_at DESC
        LIMIT p_limit OFFSET p_offset
      ) c
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_verifications_bundle(
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
  v_outcome text := nullif(trim(p_filters->>'verification_outcome'), '');
  v_total bigint;
  v_reviewed bigint;
  v_approved bigint;
  v_rejected bigint;
  v_avg_days numeric;
BEGIN
  SELECT count(*) INTO v_reviewed
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.reviewed_at >= p_from AND v.reviewed_at < p_to
    AND v.verification_status IN (
      'approved'::public.verification_status_enum,
      'rejected'::public.verification_status_enum
    );

  SELECT count(*) INTO v_approved
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.reviewed_at >= p_from AND v.reviewed_at < p_to
    AND v.verification_status = 'approved'::public.verification_status_enum;

  SELECT count(*) INTO v_rejected
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.reviewed_at >= p_from AND v.reviewed_at < p_to
    AND v.verification_status = 'rejected'::public.verification_status_enum;

  SELECT avg(extract(epoch FROM (v.reviewed_at - v.submitted_at)) / 86400.0) INTO v_avg_days
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.reviewed_at >= p_from AND v.reviewed_at < p_to
    AND v.submitted_at IS NOT NULL;

  summary := jsonb_build_array(
    public._admin_report_metric('submitted', 'Applications submitted',
      (SELECT count(*) FROM public.user_verifications v
       WHERE v.application_type = 'seller'
         AND v.submitted_at >= p_from AND v.submitted_at < p_to)),
    public._admin_report_metric('pending', 'Pending (snapshot)',
      (SELECT count(*) FROM public.user_verifications v
       WHERE v.application_type = 'seller'
         AND v.verification_status = 'pending'::public.verification_status_enum), 'count', true),
    public._admin_report_metric('approved', 'Approved in period', v_approved),
    public._admin_report_metric('rejected', 'Rejected in period', v_rejected),
    public._admin_report_metric('processed', 'Processed in period', v_reviewed),
    public._admin_report_metric('approval_rate', 'Approval rate (reviewed)',
      CASE WHEN v_reviewed = 0 THEN 0 ELSE round((v_approved::numeric / v_reviewed) * 100, 1) END, 'percent'),
    public._admin_report_metric('avg_processing_days', 'Avg processing (days)', coalesce(v_avg_days, 0))
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Outcomes (reviewed in period)',
      'columns', jsonb_build_array('Outcome', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(v.verification_status::text, v.cnt)), '[]'::jsonb)
        FROM (
          SELECT verification_status, count(*) AS cnt
          FROM public.user_verifications
          WHERE application_type = 'seller'
            AND reviewed_at >= p_from AND reviewed_at < p_to
          GROUP BY 1
        ) v
      )
    )
  );

  limitations := jsonb_build_array(
    'Government ID images, selfies, and ID numbers are never included in exports.',
    'Only seller application_type rows are counted.'
  );

  SELECT count(*) INTO v_total
  FROM public.user_verifications v
  WHERE v.application_type = 'seller'
    AND v.submitted_at >= p_from AND v.submitted_at < p_to
    AND (v_outcome IS NULL OR v.verification_status::text = v_outcome);

  details := jsonb_build_object(
    'columns', jsonb_build_array('Submitted', 'Status', 'Reviewed', 'Rejection reason'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        to_char(v.submitted_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
        v.verification_status::text,
        coalesce(to_char(v.reviewed_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'), '—'),
        left(coalesce(v.rejection_reason, '—'), 80)
      ))
      FROM public.user_verifications v
      WHERE v.application_type = 'seller'
        AND v.submitted_at >= p_from AND v.submitted_at < p_to
        AND (v_outcome IS NULL OR v.verification_status::text = v_outcome)
      ORDER BY v.submitted_at DESC
      LIMIT p_limit OFFSET p_offset
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_report_security_bundle(
  p_from timestamptz,
  p_to timestamptz,
  p_cf timestamptz,
  p_ct timestamptz,
  p_filters jsonb,
  p_limit integer,
  p_offset integer,
  p_super boolean
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
  v_cat text := nullif(trim(p_filters->>'event_category'), '');
  v_total bigint := 0;
BEGIN
  summary := jsonb_build_array(
    public._admin_report_metric('bidding_violations', 'Bidding violations',
      (SELECT count(*) FROM public.auction_bidding_violations v
       WHERE v.created_at >= p_from AND v.created_at < p_to)),
    public._admin_report_metric('repeat_violators', 'Repeat violations (2+ in period)',
      (SELECT count(*) FROM public.auction_bidding_violations v
       WHERE v.created_at >= p_from AND v.created_at < p_to AND v.violation_number >= 2)),
    public._admin_report_metric('banned_snapshot', 'Banned marketplace users (snapshot)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'banned'::public.account_status_enum), 'count', true),
    public._admin_report_metric('bidding_restricted', 'Bidding restricted (snapshot)',
      (SELECT count(*) FROM public.auction_bidding_sanctions s
       WHERE s.restricted_until IS NOT NULL AND s.restricted_until > now()), 'count', true)
  );

  IF p_super THEN
    summary := summary || jsonb_build_array(
      public._admin_report_metric('audit_events', 'Admin audit events in period',
        (SELECT count(*) FROM public.admin_audit_logs l
         WHERE l.created_at >= p_from AND l.created_at < p_to)),
      public._admin_report_metric('audit_failed', 'Failed/blocked admin events',
        (SELECT count(*) FROM public.admin_audit_logs l
         WHERE l.created_at >= p_from AND l.created_at < p_to
           AND l.status IN ('failed', 'blocked')))
    );
  END IF;

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Violation consequences (period)',
      'columns', jsonb_build_array('Consequence', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(v.consequence, v.cnt)), '[]'::jsonb)
        FROM (
          SELECT consequence, count(*) AS cnt
          FROM public.auction_bidding_violations
          WHERE created_at >= p_from AND created_at < p_to
          GROUP BY 1
        ) v
      )
    )
  );

  limitations := jsonb_build_array(
    'Audit log detail is limited to super admins.',
    'Not every failed RPC writes an audit row.',
    'Ordinary page views are not security incidents.'
  );

  IF p_super THEN
    SELECT count(*) INTO v_total
    FROM public.admin_audit_logs l
    WHERE l.created_at >= p_from AND l.created_at < p_to
      AND (v_cat IS NULL OR l.category = v_cat);

    details := jsonb_build_object(
      'columns', jsonb_build_array('When', 'Category', 'Event', 'Status', 'Summary'),
      'rows', coalesce((
        SELECT jsonb_agg(jsonb_build_array(
          to_char(l.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
          l.category,
          l.event_type,
          l.status,
          left(l.summary, 120)
        ))
        FROM public.admin_audit_logs l
        WHERE l.created_at >= p_from AND l.created_at < p_to
          AND (v_cat IS NULL OR l.category = v_cat)
        ORDER BY l.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ), '[]'::jsonb),
      'total', v_total,
      'truncated', v_total > (p_offset + p_limit)
    );
  ELSE
    SELECT count(*) INTO v_total
    FROM public.auction_bidding_violations v
    WHERE v.created_at >= p_from AND v.created_at < p_to;

    details := jsonb_build_object(
      'columns', jsonb_build_array('When', 'User', 'Violation #', 'Consequence'),
      'rows', coalesce((
        SELECT jsonb_agg(jsonb_build_array(
          to_char(v.created_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI'),
          left(v.user_id::text, 8),
          v.violation_number,
          v.consequence
        ))
        FROM public.auction_bidding_violations v
        WHERE v.created_at >= p_from AND v.created_at < p_to
        ORDER BY v.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ), '[]'::jsonb),
      'total', v_total,
      'truncated', v_total > (p_offset + p_limit)
    );
  END IF;

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_marketplace_report(
  text, timestamptz, timestamptz, timestamptz, timestamptz, jsonb, integer, integer
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_marketplace_report(
  text, timestamptz, timestamptz, timestamptz, timestamptz, jsonb, integer, integer
) TO authenticated;
