-- Users report: drop redundant account status breakdown (covered by summary metrics).

CREATE OR REPLACE FUNCTION public._admin_report_users_bundle(
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
  v_summary jsonb;
  v_comparison jsonb := '[]'::jsonb;
  v_breakdowns jsonb;
  v_details jsonb;
  v_limitations jsonb;
  v_total bigint;
  v_account_type text := nullif(trim(p_filters->>'account_type'), '');
  v_account_status text := nullif(trim(p_filters->>'account_status'), '');
BEGIN
  SELECT jsonb_build_array(
    public._admin_report_metric('total_marketplace', 'Total marketplace users',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)), 'count', true),
    public._admin_report_metric('buyer_only', 'Buyer only (current)',
      (SELECT count(*) FROM public.users u
       LEFT JOIN public.seller_profiles sp ON sp.seller_id = u.user_id
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false))), 'count', true),
    public._admin_report_metric('buyer_and_seller', 'Buyer and seller (current)',
      (SELECT count(*) FROM public.users u
       LEFT JOIN public.seller_profiles sp ON sp.seller_id = u.user_id
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false))), 'count', true),
    public._admin_report_metric('new_registrations', 'New registrations',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.created_at >= p_from AND u.created_at < p_to)),
    public._admin_report_metric('active_accounts', 'Active accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'active'::public.account_status_enum), 'count', true),
    public._admin_report_metric('disabled_accounts', 'Disabled accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'suspended'::public.account_status_enum), 'count', true),
    public._admin_report_metric('banned_accounts', 'Banned accounts (current)',
      (SELECT count(*) FROM public.users u
       WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
         AND u.account_status = 'banned'::public.account_status_enum), 'count', true),
    public._admin_report_metric('sellers_approved_period', 'Sellers approved in period',
      (SELECT count(*) FROM public.user_verifications v
       WHERE v.application_type = 'seller'
         AND v.verification_status = 'approved'::public.verification_status_enum
         AND v.reviewed_at >= p_from AND v.reviewed_at < p_to))
  ) INTO v_summary;

  IF p_cf IS NOT NULL AND p_ct IS NOT NULL AND p_ct > p_cf THEN
    v_comparison := jsonb_build_array(
      jsonb_build_object(
        'key', 'new_registrations',
        'label', 'New registrations',
        'current', (SELECT count(*) FROM public.users u
          WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
            AND u.created_at >= p_from AND u.created_at < p_to),
        'previous', (SELECT count(*) FROM public.users u
          WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
            AND u.created_at >= p_cf AND u.created_at < p_ct),
        'change_pct', NULL
      )
    );
    -- fill change_pct
    SELECT jsonb_agg(
      jsonb_set(
        elem,
        '{change_pct}',
        CASE
          WHEN (elem->>'previous')::numeric = 0 THEN 'null'::jsonb
          ELSE to_jsonb(round(
            (((elem->>'current')::numeric - (elem->>'previous')::numeric)
              / (elem->>'previous')::numeric) * 100.0, 1))
        END
      )
    ) INTO v_comparison
    FROM jsonb_array_elements(v_comparison) elem;
  END IF;

  v_breakdowns := '[]'::jsonb;

  IF p_super THEN
    v_summary := v_summary || jsonb_build_array(
      public._admin_report_metric('restrictions_applied', 'Account disables in period',
        (SELECT count(*) FROM public.admin_audit_logs l
         WHERE l.event_type = 'marketplace_account_disabled'
           AND l.created_at >= p_from AND l.created_at < p_to))
    );
  END IF;

  v_limitations := jsonb_build_array(
    'ThriftLine has no seller-only accounts; users are buyer-only or buyer+seller.',
    'Seller capability: role=seller OR seller_profiles.is_approved.',
    'Admin and super_admin accounts are excluded from marketplace user counts.'
  );

  SELECT count(*) INTO v_total
  FROM public.users u
  LEFT JOIN public.seller_profiles sp ON sp.seller_id = u.user_id
  WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
    AND u.created_at >= p_from AND u.created_at < p_to
    AND (v_account_status IS NULL OR u.account_status::text = v_account_status)
    AND (
      v_account_type IS NULL
      OR (v_account_type = 'buyer_only' AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
      OR (v_account_type = 'buyer_seller' AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
    );

  SELECT jsonb_build_object(
    'columns', jsonb_build_array('Registered', 'Account type', 'Status'),
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_array(
        public._admin_report_manila_datetime(u.created_at),
        CASE WHEN u.role = 'seller'::public.user_role_enum OR u.is_approved
          THEN 'Buyer + Seller' ELSE 'Buyer only' END,
        u.account_status::text
      ))
      FROM (
        SELECT u.user_id, u.created_at, u.role, u.account_status, coalesce(sp.is_approved, false) AS is_approved
        FROM public.users u
        LEFT JOIN public.seller_profiles sp ON sp.seller_id = u.user_id
        WHERE u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
          AND u.created_at >= p_from AND u.created_at < p_to
          AND (v_account_status IS NULL OR u.account_status::text = v_account_status)
          AND (
            v_account_type IS NULL
            OR (v_account_type = 'buyer_only' AND NOT (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
            OR (v_account_type = 'buyer_seller' AND (u.role = 'seller'::public.user_role_enum OR coalesce(sp.is_approved, false)))
          )
        ORDER BY u.created_at DESC
        LIMIT p_limit OFFSET p_offset
      ) u
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  ) INTO v_details;

  summary := v_summary;
  comparison := v_comparison;
  breakdowns := v_breakdowns;
  details := v_details;
  limitations := v_limitations;
  detail_total := v_total;
  RETURN NEXT;
END;
$$;

-- Orders bundle (abbreviated helpers inline)
