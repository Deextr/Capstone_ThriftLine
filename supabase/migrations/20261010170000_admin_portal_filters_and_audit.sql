-- Admin portal: marketplace account-type filters (buyer / seller / both) and audit log actor filter.

CREATE OR REPLACE FUNCTION public.list_marketplace_users(
  p_search text DEFAULT NULL,
  p_account_type text DEFAULT NULL,
  p_status text DEFAULT NULL,
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
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(lower(btrim(COALESCE(p_search, ''))), '');
  v_type text := NULLIF(lower(btrim(COALESCE(p_account_type, ''))), '');
  v_status text := NULLIF(lower(btrim(COALESCE(p_status, ''))), '');
  v_total bigint;
  v_rows jsonb;
  v_counts jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF v_type IS NOT NULL
     AND v_type NOT IN ('all', 'buyer', 'seller', 'both') THEN
    RAISE EXCEPTION 'invalid account type filter' USING ERRCODE = '22023';
  END IF;

  IF v_status IS NOT NULL AND v_status NOT IN (
    'all', 'active', 'suspended', 'banned', 'deactivated'
  ) THEN
    RAISE EXCEPTION 'invalid account status filter' USING ERRCODE = '22023';
  END IF;

  IF v_type = 'all' THEN v_type := NULL; END IF;
  IF v_status = 'all' THEN v_status := NULL; END IF;

  IF v_search IS NOT NULL THEN
    v_search := replace(v_search, chr(92), chr(92) || chr(92));
    v_search := replace(v_search, '%', chr(92) || '%');
    v_search := replace(v_search, '_', chr(92) || '_');
  END IF;

  SELECT count(*)::bigint INTO v_total
  FROM public._marketplace_user_rows() r
  WHERE (
      v_status IS NULL
      OR r.account_status = v_status
      OR (v_status = 'banned' AND r.trust_level = 'Banned')
    )
    AND (
      v_type IS NULL
      OR (v_type = 'buyer' AND r.account_type = 'buyer')
      OR (v_type = 'both' AND r.account_type = 'buyer_seller')
      OR (
        v_type = 'seller'
        AND r.account_type = 'buyer_seller'
        AND r.role = 'seller'::text
      )
    )
    AND (
      v_search IS NULL
      OR lower(r.full_name) LIKE '%' || v_search || '%' ESCAPE chr(92)
      OR lower(r.email) LIKE '%' || v_search || '%' ESCAPE chr(92)
      OR lower(r.username) LIKE '%' || v_search || '%' ESCAPE chr(92)
    );

  SELECT COALESCE(
    jsonb_agg(to_jsonb(page) ORDER BY page.created_at DESC, page.user_id),
    '[]'::jsonb
  )
  INTO v_rows
  FROM (
    SELECT
      r.user_id,
      r.full_name,
      r.email,
      r.username,
      r.role,
      r.account_status,
      r.account_type,
      r.created_at,
      r.seller_approved,
      r.shop_name,
      r.verification_status,
      r.trust_level,
      r.trust_score,
      public.marketplace_effective_account_status(
        r.account_status,
        r.trust_level
      ) AS display_account_status,
      (
        r.account_status = 'active'
        AND r.trust_level IS DISTINCT FROM 'Banned'
      ) AS can_disable
    FROM public._marketplace_user_rows() r
    WHERE (
        v_status IS NULL
        OR r.account_status = v_status
        OR (v_status = 'banned' AND r.trust_level = 'Banned')
      )
      AND (
        v_type IS NULL
        OR (v_type = 'buyer' AND r.account_type = 'buyer')
        OR (v_type = 'both' AND r.account_type = 'buyer_seller')
        OR (
          v_type = 'seller'
          AND r.account_type = 'buyer_seller'
          AND r.role = 'seller'::text
        )
      )
      AND (
        v_search IS NULL
        OR lower(r.full_name) LIKE '%' || v_search || '%' ESCAPE chr(92)
        OR lower(r.email) LIKE '%' || v_search || '%' ESCAPE chr(92)
        OR lower(r.username) LIKE '%' || v_search || '%' ESCAPE chr(92)
      )
    ORDER BY r.created_at DESC, r.user_id
    LIMIT v_limit
    OFFSET v_offset
  ) page;

  SELECT jsonb_build_object(
    'total', count(*),
    'active', count(*) FILTER (
      WHERE account_status = 'active' AND trust_level IS DISTINCT FROM 'Banned'
    ),
    'disabled', count(*) FILTER (WHERE account_status = 'suspended'),
    'banned', count(*) FILTER (
      WHERE account_status = 'banned' OR trust_level = 'Banned'
    )
  )
  INTO v_counts
  FROM public._marketplace_user_rows();

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'counts', v_counts,
    'rows', v_rows
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_admin_audit_logs(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_actor_user_id uuid DEFAULT NULL,
  p_actor_kind text DEFAULT NULL,
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
  v_actor_kind text := NULLIF(lower(trim(COALESCE(p_actor_kind, ''))), '');
  v_total bigint;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'super admin access required' USING ERRCODE = '42501';
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

  IF v_actor_kind IS NOT NULL
     AND v_actor_kind NOT IN ('administrator', 'super_admin', 'system') THEN
    RAISE EXCEPTION 'invalid actor filter' USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::bigint INTO v_total
  FROM public.admin_audit_logs l
  LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
  WHERE (
      v_category IS NULL
      OR v_category = 'all'
      OR l.category = v_category
      OR (
        v_category = 'account_management'
        AND l.category IN ('account_management', 'authentication')
      )
    )
    AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
    AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
    AND (
      v_actor_kind IS NULL
      OR (
        v_actor_kind = 'system'
        AND l.actor_user_id IS NULL
      )
      OR (
        v_actor_kind = 'super_admin'
        AND actor.role = 'super_admin'::public.user_role_enum
      )
      OR (
        v_actor_kind = 'administrator'
        AND actor.role = 'admin'::public.user_role_enum
      )
    )
    AND (p_from IS NULL OR l.created_at >= p_from)
    AND (p_to IS NULL OR l.created_at < p_to)
    AND (
      v_search IS NULL
      OR l.summary ILIKE ('%' || v_search || '%')
      OR l.event_type ILIKE ('%' || v_search || '%')
      OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(l.target_type, '') ILIKE ('%' || v_search || '%')
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
      actor.full_name AS actor_full_name,
      actor.role::text AS actor_role,
      l.target_type,
      l.target_id,
      l.details
    FROM public.admin_audit_logs l
    LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
    WHERE (
        v_category IS NULL
        OR v_category = 'all'
        OR l.category = v_category
        OR (
          v_category = 'account_management'
          AND l.category IN ('account_management', 'authentication')
        )
      )
      AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
      AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
      AND (
        v_actor_kind IS NULL
        OR (
          v_actor_kind = 'system'
          AND l.actor_user_id IS NULL
        )
        OR (
          v_actor_kind = 'super_admin'
          AND actor.role = 'super_admin'::public.user_role_enum
        )
        OR (
          v_actor_kind = 'administrator'
          AND actor.role = 'admin'::public.user_role_enum
        )
      )
      AND (p_from IS NULL OR l.created_at >= p_from)
      AND (p_to IS NULL OR l.created_at < p_to)
      AND (
        v_search IS NULL
        OR l.summary ILIKE ('%' || v_search || '%')
        OR l.event_type ILIKE ('%' || v_search || '%')
        OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%')
        OR COALESCE(l.target_type, '') ILIKE ('%' || v_search || '%')
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
