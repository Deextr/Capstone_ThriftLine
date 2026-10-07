-- Server-side seller search for Report a Seller (approved, active sellers only).

CREATE OR REPLACE FUNCTION public.search_reportable_sellers(
  p_query text,
  p_limit integer DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_q text := lower(btrim(coalesce(p_query, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 20);
  v_items jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF char_length(v_q) < 2 THEN
    RETURN jsonb_build_object('success', true, 'items', '[]'::jsonb);
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(m)), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      sp.seller_id,
      u.username,
      u.full_name,
      u.avatar,
      sp.shop_name
    FROM public.seller_profiles sp
    INNER JOIN public.users u ON u.user_id = sp.seller_id
    WHERE sp.is_approved = true
      AND u.account_status = 'active'::account_status_enum
      AND u.role = 'seller'::user_role_enum
      AND sp.seller_id IS DISTINCT FROM v_uid
      AND (
        lower(sp.shop_name) LIKE '%' || v_q || '%'
        OR lower(coalesce(u.username, '')) LIKE '%' || v_q || '%'
        OR lower(coalesce(u.full_name, '')) LIKE '%' || v_q || '%'
      )
    ORDER BY
      CASE
        WHEN lower(sp.shop_name) LIKE v_q || '%' THEN 0
        WHEN lower(coalesce(u.username, '')) LIKE v_q || '%' THEN 1
        ELSE 2
      END,
      sp.shop_name,
      u.username
    LIMIT v_limit
  ) m;

  RETURN jsonb_build_object('success', true, 'items', coalesce(v_items, '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.search_reportable_sellers(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_reportable_sellers(text, integer) TO authenticated;
