-- Structured admin audit trail (read: admins only; write: service_role + admin RPC).

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  log_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  category text NOT NULL,
  event_type text NOT NULL,
  status text NOT NULL,
  summary text NOT NULL,
  actor_user_id uuid,
  actor_email text,
  target_type text,
  target_id text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_hash text,
  CONSTRAINT admin_audit_logs_status_check
    CHECK (status IN ('success', 'failed', 'blocked')),
  CONSTRAINT admin_audit_logs_category_check
    CHECK (
      category IN (
        'authentication',
        'seller_verification',
        'reports_disputes',
        'account_management',
        'payments_escrow',
        'system_security'
      )
    )
);

CREATE INDEX IF NOT EXISTS admin_audit_logs_created_at_desc_idx
  ON public.admin_audit_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS admin_audit_logs_category_idx
  ON public.admin_audit_logs (category);

CREATE INDEX IF NOT EXISTS admin_audit_logs_event_type_idx
  ON public.admin_audit_logs (event_type);

CREATE INDEX IF NOT EXISTS admin_audit_logs_actor_user_id_idx
  ON public.admin_audit_logs (actor_user_id)
  WHERE actor_user_id IS NOT NULL;

ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.admin_audit_logs FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.admin_audit_logs FROM authenticated;
GRANT SELECT ON TABLE public.admin_audit_logs TO authenticated;

DROP POLICY IF EXISTS admin_audit_logs_select_admin ON public.admin_audit_logs;
CREATE POLICY admin_audit_logs_select_admin
  ON public.admin_audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

COMMENT ON TABLE public.admin_audit_logs IS
  'Immutable admin security and action audit trail. No client UPDATE/DELETE.';

CREATE OR REPLACE FUNCTION public.insert_admin_auth_audit_log(
  p_event_type text,
  p_status text,
  p_summary text,
  p_actor_email text DEFAULT NULL,
  p_actor_user_id uuid DEFAULT NULL,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb,
  p_ip_hash text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_details jsonb := COALESCE(p_details, '{}'::jsonb);
BEGIN
  IF p_event_type IS NULL OR length(trim(p_event_type)) = 0 THEN
    RAISE EXCEPTION 'event_type required' USING ERRCODE = '22023';
  END IF;
  IF p_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid audit status' USING ERRCODE = '22023';
  END IF;
  IF p_summary IS NULL OR length(trim(p_summary)) = 0 THEN
    RAISE EXCEPTION 'summary required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.admin_audit_logs (
    category,
    event_type,
    status,
    summary,
    actor_user_id,
    actor_email,
    target_type,
    target_id,
    details,
    ip_hash
  )
  VALUES (
    'authentication',
    trim(p_event_type),
    p_status,
    left(trim(p_summary), 500),
    p_actor_user_id,
    CASE
      WHEN p_actor_email IS NULL OR length(trim(p_actor_email)) = 0 THEN NULL
      ELSE left(trim(lower(p_actor_email)), 320)
    END,
    NULLIF(trim(p_target_type), ''),
    NULLIF(trim(p_target_id), ''),
    v_details,
    NULLIF(trim(p_ip_hash), '')
  )
  RETURNING log_id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.insert_admin_auth_audit_log(
  text, text, text, text, uuid, text, text, jsonb, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.insert_admin_auth_audit_log(
  text, text, text, text, uuid, text, text, jsonb, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.record_admin_audit_log(
  p_category text,
  p_event_type text,
  p_status text,
  p_summary text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_email text;
  v_details jsonb := COALESCE(p_details, '{}'::jsonb);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_category NOT IN (
    'authentication',
    'seller_verification',
    'reports_disputes',
    'account_management',
    'payments_escrow',
    'system_security'
  ) THEN
    RAISE EXCEPTION 'invalid audit category' USING ERRCODE = '22023';
  END IF;

  IF p_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid audit status' USING ERRCODE = '22023';
  END IF;

  IF p_event_type IS NULL OR length(trim(p_event_type)) = 0
     OR p_summary IS NULL OR length(trim(p_summary)) = 0 THEN
    RAISE EXCEPTION 'event_type and summary required' USING ERRCODE = '22023';
  END IF;

  SELECT u.email INTO v_email
  FROM public.users u
  WHERE u.user_id = auth.uid();

  INSERT INTO public.admin_audit_logs (
    category,
    event_type,
    status,
    summary,
    actor_user_id,
    actor_email,
    target_type,
    target_id,
    details
  )
  VALUES (
    p_category,
    trim(p_event_type),
    p_status,
    left(trim(p_summary), 500),
    auth.uid(),
    v_email,
    NULLIF(trim(p_target_type), ''),
    NULLIF(trim(p_target_id), ''),
    v_details
  )
  RETURNING log_id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_admin_audit_log(
  text, text, text, text, text, text, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_admin_audit_log(
  text, text, text, text, text, text, jsonb
) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_admin_audit_logs(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_actor_user_id uuid DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(trim(COALESCE(p_search, '')), '');
  v_category text := NULLIF(trim(COALESCE(p_category, '')), '');
  v_status text := NULLIF(trim(COALESCE(p_status, '')), '');
  v_total bigint;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF v_category IS NOT NULL AND v_category <> 'all'
     AND v_category NOT IN (
       'authentication',
       'seller_verification',
       'reports_disputes',
       'account_management',
       'payments_escrow',
       'system_security'
     ) THEN
    RAISE EXCEPTION 'invalid category filter' USING ERRCODE = '22023';
  END IF;

  IF v_status IS NOT NULL AND v_status <> 'all'
     AND v_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid status filter' USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::bigint INTO v_total
  FROM public.admin_audit_logs l
  WHERE (v_category IS NULL OR v_category = 'all' OR l.category = v_category)
    AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
    AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
    AND (p_from IS NULL OR l.created_at >= p_from)
    AND (p_to IS NULL OR l.created_at < p_to)
    AND (
      v_search IS NULL
      OR l.summary ILIKE ('%' || v_search || '%')
      OR l.event_type ILIKE ('%' || v_search || '%')
      OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT
      l.log_id,
      l.created_at,
      l.category,
      l.event_type,
      l.status,
      l.summary,
      l.actor_user_id,
      l.actor_email,
      l.target_type,
      l.target_id,
      l.details
    FROM public.admin_audit_logs l
    WHERE (v_category IS NULL OR v_category = 'all' OR l.category = v_category)
      AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
      AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
      AND (p_from IS NULL OR l.created_at >= p_from)
      AND (p_to IS NULL OR l.created_at < p_to)
      AND (
        v_search IS NULL
        OR l.summary ILIKE ('%' || v_search || '%')
        OR l.event_type ILIKE ('%' || v_search || '%')
        OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
      )
    ORDER BY l.created_at DESC, l.log_id DESC
    LIMIT v_limit
    OFFSET v_offset
  ) x;

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_admin_audit_logs(
  text, text, text, uuid, timestamptz, timestamptz, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_admin_audit_logs(
  text, text, text, uuid, timestamptz, timestamptz, integer, integer
) TO authenticated;
