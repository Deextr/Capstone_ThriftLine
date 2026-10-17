-- Admin portal: list buyer refunds (PayMongo + manual GCash follow-up).

CREATE OR REPLACE FUNCTION public.admin_list_buyer_refunds(
  p_status text DEFAULT NULL,
  p_search text DEFAULT NULL,
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
  v_status text := NULLIF(lower(btrim(coalesce(p_status, ''))), '');
  v_search text := NULLIF(btrim(coalesce(p_search, '')), '');
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 25), 100));
  v_offset integer := GREATEST(0, COALESCE(p_offset, 0));
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_counts jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required.');
  END IF;

  IF v_status IS NOT NULL
     AND v_status NOT IN ('needs_action', 'in_progress', 'completed', 'all') THEN
    v_status := NULL;
  END IF;

  WITH base AS (
    SELECT
      e.escrow_id,
      e.order_id,
      e.amount_centavos,
      e.refund_state,
      e.refund_provider_status,
      e.refund_lock_at,
      e.refunded_at,
      e.paymongo_refund_id,
      o.order_number,
      o.buyer_id,
      u.full_name AS buyer_name,
      u.email AS buyer_email,
      d.gcash_account_name,
      d.gcash_mobile_number,
      (d.gcash_submitted_at IS NOT NULL) AS buyer_gcash_submitted,
      (NULLIF(btrim(coalesce(d.transfer_link, '')), '') IS NOT NULL) AS has_claim_link
    FROM public.escrow e
    JOIN public.orders o ON o.order_id = e.order_id
    JOIN public.users u ON u.user_id = o.buyer_id
    LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
    WHERE e.status = 'refunded'::public.escrow_status_enum
      AND e.refund_state IS NOT NULL
  ),
  filtered AS (
    SELECT *
    FROM base b
    WHERE (
        v_status IS NULL
        OR v_status = 'all'
        OR (v_status = 'needs_action'
            AND b.refund_state = 'manual_required'::public.escrow_refund_state_enum)
        OR (v_status = 'in_progress'
            AND b.refund_state IN (
              'provider_pending'::public.escrow_refund_state_enum,
              'awaiting_buyer_claim'::public.escrow_refund_state_enum
            ))
        OR (v_status = 'completed'
            AND b.refund_state IN (
              'succeeded'::public.escrow_refund_state_enum,
              'manual_completed'::public.escrow_refund_state_enum
            ))
      )
      AND (
        v_search IS NULL
        OR b.order_number ILIKE '%' || v_search || '%'
        OR b.escrow_id::text = v_search
        OR b.order_id::text = v_search
        OR b.buyer_name ILIKE '%' || v_search || '%'
        OR b.buyer_email ILIKE '%' || v_search || '%'
        OR b.paymongo_refund_id ILIKE '%' || v_search || '%'
        OR b.gcash_mobile_number ILIKE '%' || v_search || '%'
        OR b.gcash_account_name ILIKE '%' || v_search || '%'
      )
  )
  SELECT
    (SELECT COUNT(*) FROM filtered),
    COALESCE((
      SELECT jsonb_agg(row_item ORDER BY sort_refunded DESC)
      FROM (
        SELECT
          jsonb_build_object(
            'escrow_id', f.escrow_id,
            'order_id', f.order_id,
            'order_number', f.order_number,
            'buyer_id', f.buyer_id,
            'buyer_name', f.buyer_name,
            'buyer_email', f.buyer_email,
            'amount_centavos', f.amount_centavos,
            'refund_state', f.refund_state::text,
            'refund_provider_status', f.refund_provider_status,
            'refund_locked', f.refund_lock_at IS NOT NULL,
            'refunded_at', f.refunded_at,
            'paymongo_refund_id', f.paymongo_refund_id,
            'buyer_gcash_submitted', f.buyer_gcash_submitted,
            'gcash_account_name', f.gcash_account_name,
            'gcash_mobile_number', f.gcash_mobile_number,
            'has_claim_link', f.has_claim_link
          ) AS row_item,
          f.refunded_at AS sort_refunded
        FROM filtered f
        ORDER BY f.refunded_at DESC NULLS LAST, f.escrow_id
        LIMIT v_limit OFFSET v_offset
      ) page
    ), '[]'::jsonb)
  INTO v_total, v_items;

  WITH base AS (
    SELECT e.refund_state
    FROM public.escrow e
    WHERE e.status = 'refunded'::public.escrow_status_enum
      AND e.refund_state IS NOT NULL
  )
  SELECT jsonb_build_object(
    'needs_action', COUNT(*) FILTER (
      WHERE refund_state = 'manual_required'::public.escrow_refund_state_enum
    ),
    'in_progress', COUNT(*) FILTER (
      WHERE refund_state IN (
        'provider_pending'::public.escrow_refund_state_enum,
        'awaiting_buyer_claim'::public.escrow_refund_state_enum
      )
    ),
    'completed', COUNT(*) FILTER (
      WHERE refund_state IN (
        'succeeded'::public.escrow_refund_state_enum,
        'manual_completed'::public.escrow_refund_state_enum
      )
    )
  )
  INTO v_counts
  FROM base;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'items', v_items,
    'counts', v_counts
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_buyer_refunds(text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_buyer_refunds(text, text, integer, integer)
  TO authenticated;
