-- Disputes detail: show Not yet resolved when unresolved (fixes mojibake em dash).

-- Disputes report: public.reports uses category (not reason); looking_for_reports uses reason.
-- Detail pagination uses subquery before jsonb_agg.

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
    'Community and order rows show report category; Looking For rows show reason.',
    'No admin review SLA is defined; overdue review counts are omitted.',
    'Evidence files and private details are excluded from detail rows.'
  );

  WITH combined AS (
    SELECT 'community'::text AS typ, r.report_id::text AS id, r.status::text AS st,
           r.category::text AS reason_label, r.created_at, r.resolved_at
    FROM public.reports r
    WHERE r.order_id IS NULL AND r.created_at >= p_from AND r.created_at < p_to
    UNION ALL
    SELECT 'order', r.report_id::text, r.status::text, r.category::text, r.created_at, r.resolved_at
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
    'columns', jsonb_build_array('Type', 'Status', 'Reason / category', 'Submitted', 'Resolved'),
    'rows', coalesce((
      SELECT jsonb_agg(src.row_data)
      FROM (
        WITH combined AS (
          SELECT 'community'::text AS typ, r.status::text AS st, r.category::text AS reason_label,
                 r.created_at, r.resolved_at
          FROM public.reports r
          WHERE r.order_id IS NULL AND r.created_at >= p_from AND r.created_at < p_to
          UNION ALL
          SELECT 'order', r.status::text, r.category::text, r.created_at, r.resolved_at
          FROM public.reports r
          WHERE r.order_id IS NOT NULL AND r.created_at >= p_from AND r.created_at < p_to
          UNION ALL
          SELECT 'looking_for', l.status::text, l.reason, l.created_at, l.resolved_at
          FROM public.looking_for_reports l
          WHERE l.created_at >= p_from AND l.created_at < p_to
        )
        SELECT jsonb_build_array(
          c.typ,
          c.st,
          left(replace(c.reason_label, '_', ' '), 60),
          public._admin_report_manila_datetime(c.created_at),
          coalesce(public._admin_report_manila_datetime(c.resolved_at), 'Not yet resolved')
        ) AS row_data
        FROM combined c
        WHERE (v_type IS NULL OR c.typ = v_type)
          AND (v_status IS NULL OR c.st = v_status)
        ORDER BY c.created_at DESC
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