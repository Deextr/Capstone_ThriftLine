-- Date-range Admin Dashboard snapshot.
-- Replaces admin_dashboard_snapshot(integer) with from/to timestamps so
-- Today / 7 days / last month / last year / custom range are queried in SQL.
--
-- Period metrics use created_at / last_active_at / submitted_at in [p_from, p_to).
-- Current-state queues (pending verifications, open reports, open disputes)
-- stay unfiltered so "currently waiting" is not rewritten as "created in range".
--
-- Idempotent. Do not edit earlier migrations.

DROP FUNCTION IF EXISTS public.admin_dashboard_snapshot(integer);

CREATE OR REPLACE FUNCTION public.admin_dashboard_snapshot(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_from timestamptz;
  v_to timestamptz;
  v_from_date date;
  v_to_date date;
  v_span integer;
  v_month boolean;
  v_active_minutes integer := 15;
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

  v_from := coalesce(p_from, date_trunc('day', timezone('UTC', now())));
  v_to := coalesce(p_to, now());
  IF v_to <= v_from THEN
    v_to := v_from + interval '1 day';
  END IF;

  v_from_date := (timezone('UTC', v_from))::date;
  v_to_date := (timezone('UTC', v_to - interval '1 millisecond'))::date;
  IF v_to_date < v_from_date THEN
    v_to_date := v_from_date;
  END IF;
  v_span := (v_to_date - v_from_date) + 1;
  v_month := v_span > 62;

  SELECT jsonb_build_object(
    'success', true,
    'generated_at', now(),
    'range_from', v_from,
    'range_to', v_to,
    'bucket', CASE WHEN v_month THEN 'month' ELSE 'day' END,
    'active_window_minutes', v_active_minutes,
    'counts', jsonb_build_object(
      'period_users', (
        SELECT count(*)::int FROM public.users u
        WHERE u.created_at >= v_from AND u.created_at < v_to
      ),
      'period_active', (
        SELECT count(*)::int
        FROM public.users u
        WHERE u.account_status = 'active'::public.account_status_enum
          AND u.last_active_at IS NOT NULL
          AND u.last_active_at >= v_from
          AND u.last_active_at < v_to
      ),
      'active_now', (
        SELECT count(*)::int
        FROM public.users u
        WHERE u.account_status = 'active'::public.account_status_enum
          AND u.last_active_at IS NOT NULL
          AND u.last_active_at >= now() - make_interval(mins => v_active_minutes)
      ),
      'pending_verifications', (
        SELECT count(*)::int
        FROM public.user_verifications v
        WHERE v.verification_status = 'pending'::public.verification_status_enum
      ),
      'period_verifications', (
        SELECT count(*)::int
        FROM public.user_verifications v
        WHERE v.submitted_at >= v_from AND v.submitted_at < v_to
      ),
      'open_reports', (
        SELECT count(*)::int
        FROM public.reports r
        WHERE r.status = 'under_review'::public.report_status_enum
      ),
      'period_reports', (
        SELECT count(*)::int
        FROM public.reports r
        WHERE r.created_at >= v_from AND r.created_at < v_to
      ),
      'period_orders', (
        SELECT count(*)::int
        FROM public.orders o
        WHERE o.created_at >= v_from AND o.created_at < v_to
      ),
      'open_disputes', (
        SELECT count(*)::int
        FROM public.delivery_disputes d
        WHERE d.status = 'open'::public.delivery_dispute_status_enum
      )
    ),
    'registrations', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'day', to_char(g.ts::date, 'YYYY-MM-DD'),
          'count', coalesce(c.cnt, 0)
        )
        ORDER BY g.ts
      ), '[]'::jsonb)
      FROM generate_series(
        CASE WHEN v_month THEN date_trunc('month', v_from_date::timestamp)
             ELSE v_from_date::timestamp END,
        CASE WHEN v_month THEN date_trunc('month', v_to_date::timestamp)
             ELSE v_to_date::timestamp END,
        CASE WHEN v_month THEN interval '1 month' ELSE interval '1 day' END
      ) AS g(ts)
      LEFT JOIN (
        SELECT
          CASE WHEN v_month THEN date_trunc('month', timezone('UTC', u.created_at))::date
               ELSE (timezone('UTC', u.created_at))::date END AS day,
          count(*)::int AS cnt
        FROM public.users u
        WHERE u.created_at >= v_from AND u.created_at < v_to
        GROUP BY 1
      ) c ON c.day = g.ts::date
    ),
    'reports_by_day', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'day', to_char(g.ts::date, 'YYYY-MM-DD'),
          'count', coalesce(c.cnt, 0)
        )
        ORDER BY g.ts
      ), '[]'::jsonb)
      FROM generate_series(
        CASE WHEN v_month THEN date_trunc('month', v_from_date::timestamp)
             ELSE v_from_date::timestamp END,
        CASE WHEN v_month THEN date_trunc('month', v_to_date::timestamp)
             ELSE v_to_date::timestamp END,
        CASE WHEN v_month THEN interval '1 month' ELSE interval '1 day' END
      ) AS g(ts)
      LEFT JOIN (
        SELECT
          CASE WHEN v_month THEN date_trunc('month', timezone('UTC', r.created_at))::date
               ELSE (timezone('UTC', r.created_at))::date END AS day,
          count(*)::int AS cnt
        FROM public.reports r
        WHERE r.created_at >= v_from AND r.created_at < v_to
        GROUP BY 1
      ) c ON c.day = g.ts::date
    ),
    'reports_by_status', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      ), '[]'::jsonb)
      FROM (
        SELECT r.status::text AS status, count(*)::int AS cnt
        FROM public.reports r
        WHERE r.created_at >= v_from AND r.created_at < v_to
        GROUP BY 1
      ) s
    ),
    'pending_verifications', (
      SELECT coalesce(jsonb_agg(item ORDER BY submitted_at DESC), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'id', v.verification_id,
          'applicant_name', coalesce(nullif(trim(u.full_name), ''), 'Applicant'),
          'shop_name', coalesce(nullif(trim(v.shop_name), ''), 'Shop'),
          'submitted_at', v.submitted_at,
          'status', v.verification_status::text
        ) AS item,
        v.submitted_at
        FROM public.user_verifications v
        JOIN public.users u ON u.user_id = v.user_id
        WHERE v.verification_status = 'pending'::public.verification_status_enum
        ORDER BY v.submitted_at DESC
        LIMIT 8
      ) q
    ),
    'recent_reports', (
      SELECT coalesce(jsonb_agg(item ORDER BY created_at DESC), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'id', r.report_id,
          'reporter_name', coalesce(
            nullif(trim(reporter.full_name), ''),
            coalesce(nullif(trim(reporter.username), ''), 'Member')
          ),
          'reporter_role', reporter.role::text,
          'reported_name', coalesce(
            nullif(trim(reported.full_name), ''),
            coalesce(nullif(trim(reported.username), ''), 'Member')
          ),
          'reported_role', reported.role::text,
          'category', r.category,
          'order_number', o.order_number,
          'created_at', r.created_at,
          'status', r.status::text
        ) AS item,
        r.created_at
        FROM public.reports r
        JOIN public.users reporter ON reporter.user_id = r.reporter_id
        JOIN public.users reported ON reported.user_id = r.reported_user_id
        LEFT JOIN public.orders o ON o.order_id = r.order_id
        WHERE r.created_at >= v_from AND r.created_at < v_to
        ORDER BY r.created_at DESC
        LIMIT 5
      ) q
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz) IS
  'Admin-only dashboard for [p_from, p_to). Period counts use timestamps. Pending verifications and open reports are current-state queues.';

REVOKE ALL ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz)
  TO authenticated;
