-- Fix list/get confirmed violations: orders have product_id on order_items, not orders.

CREATE OR REPLACE FUNCTION public._confirmed_violation_product_name(p_order_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT nullif(btrim(pr.name), '')
  FROM public.order_items oi
  JOIN public.products pr ON pr.product_id = oi.product_id
  WHERE oi.order_id = p_order_id
  ORDER BY oi.created_at ASC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.list_my_confirmed_violations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT coalesce(
    jsonb_agg(row ORDER BY (row->>'confirmed_at')::timestamptz DESC),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'source', 'looking_for',
      'record_id', v.violation_id,
      'category', 'looking_for',
      'confirmed_at', v.created_at,
      'strike_number', v.strike_number,
      'post_id', v.post_id,
      'report_id', v.report_id,
      'reference_title', coalesce(
        nullif(btrim(r.snapshot_title), ''),
        nullif(btrim(p.title), ''),
        'Looking For post'
      ),
      'reason', r.reason,
      'penalty_status', CASE
        WHEN s.permanently_disabled_at IS NOT NULL THEN 'permanent_disable'
        WHEN s.restricted_until IS NOT NULL AND s.restricted_until > now() THEN 'restricted'
        ELSE 'recorded'
      END
    ) AS row
    FROM public.looking_for_violations v
    LEFT JOIN public.looking_for_reports r ON r.report_id = v.report_id
    LEFT JOIN public.looking_for_posts p ON p.post_id = v.post_id
    LEFT JOIN public.looking_for_account_sanctions s ON s.user_id = v.user_id
    WHERE v.user_id = v_uid

    UNION ALL

    SELECT jsonb_build_object(
      'source', 'auction_bidding',
      'record_id', v.violation_id,
      'category', 'auction_bidding',
      'confirmed_at', v.created_at,
      'violation_number', v.violation_number,
      'consequence', v.consequence,
      'order_id', v.order_id,
      'auction_id', v.auction_id,
      'reference_title', coalesce(
        public._confirmed_violation_product_name(v.order_id),
        'Auction order'
      ),
      'penalty_status', CASE
        WHEN abs.permanently_disabled_at IS NOT NULL THEN 'permanent_disable'
        WHEN abs.restricted_until IS NOT NULL AND abs.restricted_until > now() THEN 'restricted'
        WHEN v.consequence = 'warning' THEN 'warning'
        ELSE 'recorded'
      END
    ) AS row
    FROM public.auction_bidding_violations v
    LEFT JOIN public.auction_bidding_sanctions abs ON abs.user_id = v.user_id
    WHERE v.user_id = v_uid

    UNION ALL

    SELECT jsonb_build_object(
      'source', 'community_report',
      'record_id', r.report_id,
      'category', r.category,
      'confirmed_at', coalesce(r.resolved_at, r.updated_at, r.created_at),
      'order_id', r.order_id,
      'report_id', r.report_id,
      'source_kind', r.source,
      'enforcement_reason', r.enforcement_reason,
      'resolution_financial', r.resolution_financial,
      'reference_title', CASE
        WHEN r.order_id IS NOT NULL THEN coalesce(
          public._confirmed_violation_product_name(r.order_id),
          'Order'
        )
        ELSE 'Community report'
      END,
      'penalty_status', 'resolved'
    ) AS row
    FROM public.reports r
    WHERE r.reported_user_id = v_uid
      AND r.status = 'resolved'::public.report_status_enum
  ) combined;

  RETURN jsonb_build_object('success', true, 'violations', v_items);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_confirmed_violation(
  p_source text,
  p_record_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_source text := lower(btrim(coalesce(p_source, '')));
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_record_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Violation not found.');
  END IF;

  IF v_source = 'looking_for' THEN
    SELECT jsonb_build_object(
        'success', true,
        'source', 'looking_for',
        'record_id', v.violation_id,
        'category', 'looking_for',
        'confirmed_at', v.created_at,
        'strike_number', v.strike_number,
        'post_id', v.post_id,
        'report_id', v.report_id,
        'reason', r.reason,
        'reference_title', coalesce(
          nullif(btrim(r.snapshot_title), ''),
          nullif(btrim(p.title), ''),
          'Looking For post'
        ),
        'reference_description', coalesce(
          nullif(btrim(r.snapshot_description), ''),
          nullif(btrim(p.description), '')
        ),
        'penalty_status', CASE
          WHEN s.permanently_disabled_at IS NOT NULL THEN 'permanent_disable'
          WHEN s.restricted_until IS NOT NULL AND s.restricted_until > now() THEN 'restricted'
          ELSE 'recorded'
        END,
        'restricted_until', s.restricted_until,
        'permanently_disabled_at', s.permanently_disabled_at,
        'disable_reason', s.disable_reason,
        'total_strikes', s.strike_count,
        'can_appeal', false
      )
      FROM public.looking_for_violations v
      LEFT JOIN public.looking_for_reports r ON r.report_id = v.report_id
      LEFT JOIN public.looking_for_posts p ON p.post_id = v.post_id
      LEFT JOIN public.looking_for_account_sanctions s ON s.user_id = v.user_id
      WHERE v.violation_id = p_record_id
        AND v.user_id = v_uid
    INTO v_result;

    IF v_result IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Violation not found.');
    END IF;
    RETURN v_result;
  END IF;

  IF v_source = 'auction_bidding' THEN
    SELECT jsonb_build_object(
        'success', true,
        'source', 'auction_bidding',
        'record_id', v.violation_id,
        'category', 'auction_bidding',
        'confirmed_at', v.created_at,
        'violation_number', v.violation_number,
        'consequence', v.consequence,
        'order_id', v.order_id,
        'auction_id', v.auction_id,
        'payment_due_at', v.payment_due_at,
        'expired_at', v.expired_at,
        'reference_title', coalesce(
          public._confirmed_violation_product_name(v.order_id),
          'Auction order'
        ),
        'penalty_status', CASE
          WHEN abs.permanently_disabled_at IS NOT NULL THEN 'permanent_disable'
          WHEN abs.restricted_until IS NOT NULL AND abs.restricted_until > now() THEN 'restricted'
          WHEN v.consequence = 'warning' THEN 'warning'
          ELSE 'recorded'
        END,
        'restricted_until', abs.restricted_until,
        'permanently_disabled_at', abs.permanently_disabled_at,
        'disable_reason', abs.disable_reason,
        'total_violations', abs.violation_count,
        'can_appeal', false
      )
      FROM public.auction_bidding_violations v
      LEFT JOIN public.auction_bidding_sanctions abs ON abs.user_id = v.user_id
      WHERE v.violation_id = p_record_id
        AND v.user_id = v_uid
    INTO v_result;

    IF v_result IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Violation not found.');
    END IF;
    RETURN v_result;
  END IF;

  IF v_source = 'community_report' THEN
    SELECT jsonb_build_object(
        'success', true,
        'source', 'community_report',
        'record_id', r.report_id,
        'category', r.category,
        'confirmed_at', coalesce(r.resolved_at, r.updated_at, r.created_at),
        'order_id', r.order_id,
        'report_id', r.report_id,
        'source_kind', r.source,
        'enforcement_reason', r.enforcement_reason,
        'resolution_financial', r.resolution_financial,
        'resolution_return_required', r.resolution_return_required,
        'admin_explanation', r.admin_response,
        'reference_title', CASE
          WHEN r.order_id IS NOT NULL THEN coalesce(
            public._confirmed_violation_product_name(r.order_id),
            'Order'
          )
          ELSE 'Community report'
        END,
        'penalty_status', 'resolved',
        'can_appeal', r.status <> 'under_review'::public.report_status_enum
      )
      FROM public.reports r
      WHERE r.report_id = p_record_id
        AND r.reported_user_id = v_uid
        AND r.status = 'resolved'::public.report_status_enum
    INTO v_result;

    IF v_result IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Violation not found.');
    END IF;
    RETURN v_result;
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'Violation not found.');
END;
$$;

REVOKE ALL ON FUNCTION public._confirmed_violation_product_name(uuid) FROM PUBLIC, anon, authenticated;
