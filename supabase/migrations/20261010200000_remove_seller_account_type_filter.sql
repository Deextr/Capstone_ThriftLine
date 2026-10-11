-- Admin Users: drop legacy "seller" account-type filter (all sellers are buyer_seller).

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

  IF v_type IS NOT NULL AND v_type NOT IN ('all', 'buyer', 'both') THEN
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
