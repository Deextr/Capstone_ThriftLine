-- Marketplace User Management: restore temporarily disabled accounts and block unbanning.

-- ---------------------------------------------------------------------------
-- Column guard: banned stays banned; suspended→active only via enable RPC.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('thriftline.maintain_trust', true) IS DISTINCT FROM '1' THEN
    NEW.trust_score      := OLD.trust_score;
    NEW.trust_level      := OLD.trust_level;
    NEW.trust_breakdown  := OLD.trust_breakdown;
    NEW.trust_updated_at := OLD.trust_updated_at;
  END IF;

  IF auth.uid() IS NULL OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSIF public.is_admin()
          AND current_setting('thriftline.seller_promotion', true) = '1'
          AND OLD.role = 'buyer'::public.user_role_enum
          AND NEW.role = 'seller'::public.user_role_enum THEN
      NULL;
    ELSE
      NEW.role := OLD.role;
    END IF;
  END IF;

  IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
    IF OLD.account_status = 'banned'::public.account_status_enum THEN
      RAISE EXCEPTION
        'banned accounts cannot be reactivated through user management'
        USING ERRCODE = '42501';
    END IF;

    IF OLD.role IN (
         'buyer'::public.user_role_enum,
         'seller'::public.user_role_enum
       )
       AND NEW.role IN (
         'buyer'::public.user_role_enum,
         'seller'::public.user_role_enum
       ) THEN
      IF NEW.account_status IN (
        'banned'::public.account_status_enum,
        'deactivated'::public.account_status_enum
      ) THEN
        NULL;
      ELSIF OLD.account_status = 'active'::public.account_status_enum
         AND NEW.account_status = 'suspended'::public.account_status_enum
         AND current_setting('thriftline.marketplace_disable', true) = '1' THEN
        NULL;
      ELSIF OLD.account_status = 'suspended'::public.account_status_enum
         AND NEW.account_status = 'active'::public.account_status_enum
         AND current_setting('thriftline.marketplace_enable', true) = '1' THEN
        NULL;
      ELSE
        NEW.account_status := OLD.account_status;
      END IF;
    ELSIF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSE
      NEW.account_status := OLD.account_status;
    END IF;
  END IF;

  IF OLD.role = 'super_admin'::public.user_role_enum
     AND OLD.account_status = 'active'::public.account_status_enum
     AND (
       NEW.role IS DISTINCT FROM 'super_admin'::public.user_role_enum
       OR NEW.account_status IS DISTINCT FROM 'active'::public.account_status_enum
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.users u
       WHERE u.role = 'super_admin'::public.user_role_enum
         AND u.account_status = 'active'::public.account_status_enum
         AND u.user_id <> OLD.user_id
     )
  THEN
    RAISE EXCEPTION 'the last active super admin cannot be deactivated or demoted'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Clients cannot grant admin roles. Marketplace disable/enable require RPC session flags. Banned marketplace accounts cannot be reactivated through authenticated admin updates.';

-- ---------------------------------------------------------------------------
-- Directory helpers: can_enable for temporarily disabled accounts.
-- ---------------------------------------------------------------------------

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
      ) AS can_disable,
      (
        r.account_status = 'suspended'
        AND r.trust_level IS DISTINCT FROM 'Banned'
        AND NOT EXISTS (
          SELECT 1
          FROM public.looking_for_account_sanctions s
          WHERE s.user_id = r.user_id
            AND s.permanently_disabled_at IS NOT NULL
        )
      ) AS can_enable
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

CREATE OR REPLACE FUNCTION public.get_marketplace_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user jsonb;
  v_sanction_reason text;
  v_permanently_disabled_at timestamptz;
  v_restricted_until timestamptz;
  v_strike_count integer;
  v_admin_reason text;
  v_admin_notes text;
  v_admin_disabled_at timestamptz;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  SELECT to_jsonb(r) || jsonb_build_object(
    'display_account_status',
      public.marketplace_effective_account_status(
        r.account_status,
        r.trust_level
      ),
    'can_disable',
      r.account_status = 'active'
      AND r.trust_level IS DISTINCT FROM 'Banned',
    'can_enable',
      r.account_status = 'suspended'
      AND r.trust_level IS DISTINCT FROM 'Banned'
      AND NOT EXISTS (
        SELECT 1
        FROM public.looking_for_account_sanctions s
        WHERE s.user_id = r.user_id
          AND s.permanently_disabled_at IS NOT NULL
      )
  )
    INTO v_user
  FROM public._marketplace_user_rows() r
  WHERE r.user_id = p_user_id;

  IF v_user IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That marketplace account was not found.'
    );
  END IF;

  SELECT
    NULLIF(btrim(COALESCE(s.disable_reason, '')), ''),
    s.permanently_disabled_at,
    s.restricted_until,
    s.strike_count
  INTO
    v_sanction_reason,
    v_permanently_disabled_at,
    v_restricted_until,
    v_strike_count
  FROM public.looking_for_account_sanctions s
  WHERE s.user_id = p_user_id;

  SELECT
    NULLIF(btrim(COALESCE(l.details->>'reason', '')), ''),
    NULLIF(btrim(COALESCE(l.details->>'notes', '')), ''),
    l.created_at
  INTO v_admin_reason, v_admin_notes, v_admin_disabled_at
  FROM public.admin_audit_logs l
  WHERE l.target_type = 'user'
    AND l.target_id = p_user_id::text
    AND l.event_type = 'marketplace_account_disabled'
    AND l.status = 'success'
  ORDER BY l.created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'user', v_user || jsonb_build_object(
      'sanction_reason', v_sanction_reason,
      'permanently_disabled_at', v_permanently_disabled_at,
      'restricted_until', v_restricted_until,
      'strike_count', v_strike_count,
      'admin_disable_reason', v_admin_reason,
      'admin_disable_notes', v_admin_notes,
      'admin_disabled_at', v_admin_disabled_at
    )
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Disable (session flag for column guard).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.disable_marketplace_account(
  p_user_id uuid,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
  v_name text;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_notes text := NULLIF(btrim(COALESCE(p_notes, '')), '');
  v_updated integer := 0;
  v_after public.account_status_enum;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_reason NOT IN (
    'Violation of marketplace guidelines',
    'Fraudulent or suspicious activity',
    'Repeated abusive behavior',
    'Multiple confirmed reports',
    'Account security concerns',
    'Other policy violation'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'invalid_reason',
      'error', 'Choose a reason for disabling this account.'
    );
  END IF;

  IF v_notes IS NOT NULL AND char_length(v_notes) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'notes_too_long',
      'error', 'Keep additional notes under 1,000 characters.'
    );
  END IF;

  SELECT u.role, u.account_status, COALESCE(u.full_name, u.username, u.email, 'User')
    INTO v_role, v_status, v_name
  FROM public.users u
  WHERE u.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_role IN (
    'admin'::public.user_role_enum,
    'super_admin'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'Administrator accounts are managed separately.'
    );
  END IF;

  IF v_role NOT IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'This account cannot be managed here.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.looking_for_account_sanctions s
    WHERE s.user_id = p_user_id
      AND s.permanently_disabled_at IS NOT NULL
  ) OR v_status = 'banned'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_banned',
      'error', 'Account banned. This account is already restricted.'
    );
  END IF;

  IF v_status = 'suspended'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_disabled',
      'error', 'Account already disabled. No further disabling action is available.'
    );
  END IF;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_restricted',
      'error', 'This account is already restricted.'
    );
  END IF;

  PERFORM set_config('thriftline.marketplace_disable', '1', true);

  UPDATE public.users
  SET account_status = 'suspended'::public.account_status_enum
  WHERE user_id = p_user_id
    AND role = v_role
    AND account_status = 'active'::public.account_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  SELECT u.account_status
    INTO v_after
  FROM public.users u
  WHERE u.user_id = p_user_id;

  IF v_updated <> 1
     OR v_after IS DISTINCT FROM 'suspended'::public.account_status_enum THEN
    RAISE EXCEPTION 'This account could not be disabled.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.revoke_marketplace_sessions(p_user_id);

  PERFORM public.log_admin_action_audit(
    'account_management',
    'marketplace_account_disabled',
    'success',
    left('Disabled marketplace account ' || v_name, 500),
    'user',
    p_user_id::text,
    jsonb_build_object(
      'reason', v_reason,
      'notes', v_notes,
      'previous_status', 'active',
      'new_status', 'suspended',
      'full_name', v_name
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'account_status', 'suspended',
    'user_id', p_user_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Enable temporarily disabled marketplace accounts.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enable_marketplace_account(
  p_user_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
  v_trust text;
  v_name text;
  v_notes text := NULLIF(btrim(COALESCE(p_notes, '')), '');
  v_updated integer := 0;
  v_after public.account_status_enum;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_notes IS NOT NULL AND char_length(v_notes) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'notes_too_long',
      'error', 'Keep additional notes under 1,000 characters.'
    );
  END IF;

  SELECT u.role, u.account_status, u.trust_level,
         COALESCE(u.full_name, u.username, u.email, 'User')
    INTO v_role, v_status, v_trust, v_name
  FROM public.users u
  WHERE u.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_role IN (
    'admin'::public.user_role_enum,
    'super_admin'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'Administrator accounts are managed separately.'
    );
  END IF;

  IF v_role NOT IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'This account cannot be managed here.'
    );
  END IF;

  IF v_status = 'banned'::public.account_status_enum
     OR EXISTS (
       SELECT 1
       FROM public.looking_for_account_sanctions s
       WHERE s.user_id = p_user_id
         AND s.permanently_disabled_at IS NOT NULL
     )
     OR v_trust = 'Banned' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'banned',
      'error', 'Account banned. Reactivation is not available through User Management.'
    );
  END IF;

  IF v_status IS DISTINCT FROM 'suspended'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_disabled',
      'error', 'Only temporarily disabled accounts can be re-enabled here.'
    );
  END IF;

  PERFORM set_config('thriftline.marketplace_enable', '1', true);

  UPDATE public.users
  SET account_status = 'active'::public.account_status_enum
  WHERE user_id = p_user_id
    AND role = v_role
    AND account_status = 'suspended'::public.account_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  SELECT u.account_status
    INTO v_after
  FROM public.users u
  WHERE u.user_id = p_user_id;

  IF v_updated <> 1
     OR v_after IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RAISE EXCEPTION 'This account could not be re-enabled.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.log_admin_action_audit(
    'account_management',
    'marketplace_account_enabled',
    'success',
    left('Re-enabled marketplace account ' || v_name, 500),
    'user',
    p_user_id::text,
    jsonb_build_object(
      'notes', v_notes,
      'previous_status', 'suspended',
      'new_status', 'active',
      'full_name', v_name
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'account_status', 'active',
    'user_id', p_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.enable_marketplace_account(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enable_marketplace_account(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.enable_marketplace_account(uuid, text) IS
  'Admin-only. Restores a temporarily disabled (suspended) buyer or seller to active. Rejects banned and permanently sanctioned accounts.';
