-- Security report: audit detail column order; full summary text (no 120-char SQL cut).

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
      'columns', jsonb_build_array('Category', 'Event', 'When', 'Status', 'Summary'),
      'rows', coalesce((
        SELECT jsonb_agg(src.row_data)
        FROM (
          SELECT jsonb_build_array(
            l.category,
            l.event_type,
            public._admin_report_manila_datetime(l.created_at),
            l.status,
            coalesce(l.summary, '')
          ) AS row_data
          FROM public.admin_audit_logs l
          WHERE l.created_at >= p_from AND l.created_at < p_to
            AND (v_cat IS NULL OR l.category = v_cat)
          ORDER BY l.created_at DESC
          LIMIT p_limit OFFSET p_offset
        ) src
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
        SELECT jsonb_agg(src.row_data)
        FROM (
          SELECT jsonb_build_array(
            public._admin_report_manila_datetime(v.created_at),
            left(v.user_id::text, 8),
            v.violation_number,
            v.consequence
          ) AS row_data
          FROM public.auction_bidding_violations v
          WHERE v.created_at >= p_from AND v.created_at < p_to
          ORDER BY v.created_at DESC
          LIMIT p_limit OFFSET p_offset
        ) src
      ), '[]'::jsonb),
      'total', v_total,
      'truncated', v_total > (p_offset + p_limit)
    );
  END IF;

  detail_total := v_total;
  RETURN NEXT;
END;
$$;
