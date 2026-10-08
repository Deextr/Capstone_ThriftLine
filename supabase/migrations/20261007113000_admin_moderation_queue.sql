-- Unified admin moderation queue (reports, delivery disputes, looking-for reports).
-- Server-side filter, search, and pagination for the Admin Web Disputes module.

CREATE OR REPLACE FUNCTION public.admin_is_order_linked_report(
  p_category text,
  p_order_id uuid
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_order_id IS NOT NULL
    OR p_category = ANY (
      ARRAY[
        'fake_product',
        'counterfeit_item',
        'failure_to_ship',
        'item_not_as_described'
      ]::text[]
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_moderation_queue(
  p_category text DEFAULT 'all',
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text := lower(trim(coalesce(p_category, 'all')));
  v_status text := lower(trim(coalesce(p_status, 'all')));
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_limit integer := greatest(coalesce(p_limit, 10), 1);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_items jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can view the moderation queue.'
    );
  END IF;

  IF v_category NOT IN ('all', 'community', 'order', 'looking_for') THEN
    v_category := 'all';
  END IF;

  IF v_status NOT IN ('all', 'under_review', 'resolved', 'closed') THEN
    v_status := 'all';
  END IF;

  WITH unified AS (
    SELECT
      'report'::text AS source,
      r.report_id::text AS case_id,
      r.created_at,
      r.status::text AS status_raw,
      CASE
        WHEN public.admin_is_order_linked_report(r.category::text, r.order_id)
          THEN 'order_report'
        ELSE 'community_report'
      END AS case_kind,
      coalesce(nullif(trim(r.category), ''), 'report') AS category,
      left(coalesce(nullif(trim(r.details), ''), ''), 120) AS summary,
      coalesce(
        nullif(trim(reporter.full_name), ''),
        coalesce(nullif(trim(reporter.username), ''), 'Member')
      ) AS actor_name,
      coalesce(
        nullif(trim(reported.full_name), ''),
        coalesce(nullif(trim(reported.username), ''), 'Member')
      ) AS subject_name,
      o.order_number::text AS order_number
    FROM public.reports r
    JOIN public.users reporter ON reporter.user_id = r.reporter_id
    JOIN public.users reported ON reported.user_id = r.reported_user_id
    LEFT JOIN public.orders o ON o.order_id = r.order_id
    WHERE (
      v_category = 'all'
      OR (v_category = 'community' AND NOT public.admin_is_order_linked_report(r.category::text, r.order_id))
      OR (v_category = 'order' AND public.admin_is_order_linked_report(r.category::text, r.order_id))
    )
    UNION ALL
    SELECT
      'delivery_dispute'::text,
      d.dispute_id::text,
      d.created_at,
      d.status::text,
      'delivery_dispute'::text,
      coalesce(d.reason::text, 'delivery_problem'),
      left(coalesce(nullif(trim(d.details), ''), ''), 120),
      coalesce(
        nullif(trim(buyer.full_name), ''),
        coalesce(nullif(trim(buyer.username), ''), 'Buyer')
      ),
      coalesce(
        nullif(trim(seller.full_name), ''),
        coalesce(nullif(trim(seller.username), ''), 'Seller')
      ),
      o.order_number::text
    FROM public.delivery_disputes d
    JOIN public.users buyer ON buyer.user_id = d.buyer_id
    LEFT JOIN public.users seller ON seller.user_id = d.seller_id
    LEFT JOIN public.orders o ON o.order_id = d.order_id
    WHERE v_category IN ('all', 'order')
    UNION ALL
    SELECT
      'looking_for'::text,
      lf.report_id::text,
      lf.created_at,
      lf.status::text,
      'looking_for_report'::text,
      coalesce(nullif(trim(lf.reason), ''), 'looking_for'),
      left(coalesce(nullif(trim(lf.details), ''), ''), 120),
      coalesce(nullif(trim(lf.reporter_name), ''), lf.reporter_username, 'Member'),
      coalesce(nullif(trim(lf.reported_name), ''), lf.reported_username, 'Member'),
      NULL::text
    FROM public.admin_looking_for_report_queue lf
    WHERE v_category IN ('all', 'looking_for')
  ),
  filtered AS (
    SELECT *
    FROM unified u
    WHERE (p_from IS NULL OR u.created_at >= p_from)
      AND (p_to IS NULL OR u.created_at < p_to)
      AND (
        v_status = 'all'
        OR (v_status = 'under_review' AND (
          (u.source = 'report' AND u.status_raw = 'under_review')
          OR (u.source = 'delivery_dispute' AND u.status_raw = 'open')
          OR (u.source = 'looking_for' AND u.status_raw = 'under_review')
        ))
        OR (v_status = 'resolved' AND (
          (u.source = 'report' AND u.status_raw = 'resolved')
          OR (u.source = 'delivery_dispute' AND u.status_raw = 'resolved')
          OR (u.source = 'looking_for' AND u.status_raw = 'resolved')
        ))
        OR (v_status = 'closed' AND (
          (u.source = 'report' AND u.status_raw IN ('action_taken', 'dismissed'))
          OR (u.source = 'delivery_dispute' AND u.status_raw = 'resolved')
          OR (u.source = 'looking_for' AND u.status_raw IN ('action_taken', 'dismissed'))
        ))
      )
      AND (
        v_search IS NULL
        OR u.summary ILIKE ('%' || v_search || '%')
        OR u.category ILIKE ('%' || v_search || '%')
        OR u.actor_name ILIKE ('%' || v_search || '%')
        OR u.subject_name ILIKE ('%' || v_search || '%')
        OR coalesce(u.order_number, '') ILIKE ('%' || v_search || '%')
        OR u.case_id ILIKE ('%' || v_search || '%')
      )
  )
  SELECT count(*)::int INTO v_total FROM filtered;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source', page_row.source,
        'case_id', page_row.case_id,
        'case_kind', page_row.case_kind,
        'category', page_row.category,
        'summary', page_row.summary,
        'status_raw', page_row.status_raw,
        'actor_name', page_row.actor_name,
        'subject_name', page_row.subject_name,
        'order_number', page_row.order_number,
        'created_at', page_row.created_at
      )
      ORDER BY page_row.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      f.source,
      f.case_id,
      f.case_kind,
      f.category,
      f.summary,
      f.status_raw,
      f.actor_name,
      f.subject_name,
      f.order_number,
      f.created_at
    FROM filtered f
    ORDER BY f.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  ) page_row;

  RETURN jsonb_build_object(
    'success', true,
    'total', coalesce(v_total, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.admin_moderation_queue(text, text, text, timestamptz, timestamptz, integer, integer) IS
  'Admin Web: paginated moderation cases (community/order reports, delivery disputes, looking-for reports).';

REVOKE ALL ON FUNCTION public.admin_moderation_queue(text, text, text, timestamptz, timestamptz, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderation_queue(text, text, text, timestamptz, timestamptz, integer, integer)
  TO authenticated;
