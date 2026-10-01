-- Admin Dashboard snapshot + presence heartbeat.
--
-- Supabase Auth JWTs cannot report a reliable "online now" count.
-- `users.last_active_at` already exists; this migration:
--   1. lets signed-in clients touch their own last_active_at (throttled)
--   2. gives admins one SECURITY DEFINER RPC for dashboard totals, trends,
--      and recent queues without a query per card
--
-- "Active users" = account_status active AND last_active_at within 15 minutes.
-- Buyers/sellers cannot read the snapshot: the function re-checks is_admin().
-- The payload never includes government IDs, evidence paths, emails, or phones.
--
-- Idempotent. Safe to re-run. Do not edit earlier migrations.

CREATE INDEX IF NOT EXISTS users_last_active_at_idx
  ON public.users (last_active_at DESC)
  WHERE last_active_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS users_created_at_idx
  ON public.users (created_at);

CREATE INDEX IF NOT EXISTS orders_created_at_idx
  ON public.orders (created_at);

CREATE INDEX IF NOT EXISTS reports_created_at_idx
  ON public.reports (created_at);

-- ===========================================================================
-- 1. Presence heartbeat
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.touch_last_active()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.users
  SET last_active_at = now()
  WHERE user_id = v_uid
    AND (
      last_active_at IS NULL
      OR last_active_at < now() - interval '60 seconds'
    );
END;
$$;

COMMENT ON FUNCTION public.touch_last_active() IS
  'Authenticated users only. Updates the caller''s last_active_at at most once per minute. Used for Admin Dashboard "active in the last 15 minutes".';

REVOKE ALL ON FUNCTION public.touch_last_active() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_last_active() TO authenticated;

-- ===========================================================================
-- 2. Admin dashboard snapshot
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.admin_dashboard_snapshot(
  p_range_days integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_days integer;
  v_from timestamptz;
  v_from_date date;
  v_to_date date;
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

  v_days := CASE
    WHEN p_range_days IN (7, 30, 90) THEN p_range_days
    ELSE 30
  END;
  v_to_date := (timezone('UTC', now()))::date;
  v_from_date := v_to_date - (v_days - 1);
  v_from := v_from_date::timestamptz;

  SELECT jsonb_build_object(
    'success', true,
    'generated_at', now(),
    'range_days', v_days,
    'active_window_minutes', v_active_minutes,
    'counts', jsonb_build_object(
      'total_users', (
        SELECT count(*)::int FROM public.users
      ),
      'active_users', (
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
      'open_reports', (
        SELECT count(*)::int
        FROM public.reports r
        WHERE r.status = 'under_review'::public.report_status_enum
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
        v_from_date::timestamp,
        v_to_date::timestamp,
        interval '1 day'
      ) AS g(ts)
      LEFT JOIN (
        SELECT (timezone('UTC', u.created_at))::date AS day, count(*)::int AS cnt
        FROM public.users u
        WHERE u.created_at >= v_from
        GROUP BY 1
      ) c ON c.day = g.ts::date
    ),
    'orders_by_day', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'day', to_char(g.ts::date, 'YYYY-MM-DD'),
          'count', coalesce(c.cnt, 0)
        )
        ORDER BY g.ts
      ), '[]'::jsonb)
      FROM generate_series(
        v_from_date::timestamp,
        v_to_date::timestamp,
        interval '1 day'
      ) AS g(ts)
      LEFT JOIN (
        SELECT (timezone('UTC', o.created_at))::date AS day, count(*)::int AS cnt
        FROM public.orders o
        WHERE o.created_at >= v_from
        GROUP BY 1
      ) c ON c.day = g.ts::date
    ),
    'orders_by_status', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      ), '[]'::jsonb)
      FROM (
        SELECT o.order_status::text AS status, count(*)::int AS cnt
        FROM public.orders o
        WHERE o.created_at >= v_from
        GROUP BY 1
      ) s
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
        v_from_date::timestamp,
        v_to_date::timestamp,
        interval '1 day'
      ) AS g(ts)
      LEFT JOIN (
        SELECT (timezone('UTC', r.created_at))::date AS day, count(*)::int AS cnt
        FROM public.reports r
        WHERE r.created_at >= v_from
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
        WHERE r.created_at >= v_from
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
        ORDER BY r.created_at DESC
        LIMIT 8
      ) q
    ),
    'recent_orders', (
      SELECT coalesce(jsonb_agg(item ORDER BY created_at DESC), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'order_number', o.order_number,
          'status', o.order_status::text,
          'total_amount', o.total_amount,
          'created_at', o.created_at
        ) AS item,
        o.created_at
        FROM public.orders o
        ORDER BY o.created_at DESC
        LIMIT 8
      ) q
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_dashboard_snapshot(integer) IS
  'Admin-only dashboard payload. Active users are accounts with last_active_at in the last 15 minutes. Identity is auth.uid() via is_admin().';

REVOKE ALL ON FUNCTION public.admin_dashboard_snapshot(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_snapshot(integer) TO authenticated;
