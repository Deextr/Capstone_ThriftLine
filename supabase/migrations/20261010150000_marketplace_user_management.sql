-- Marketplace user management for the admin portal.
--
-- Listing and disabling go through SECURITY DEFINER functions so Admin and
-- Super Admin rows are excluded in the database, not only in the client.
-- `account_status = suspended` is the administrative disable. `banned` stays
-- the permanent restriction used by existing moderation. They are not the
-- same transition.
--
-- Does not disable RLS and does not grant the service role to Flutter.

-- ---------------------------------------------------------------------------
-- Active-account gate used by policies and triggers.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.user_account_is_active(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_user_id
      AND u.account_status = 'active'::public.account_status_enum
  );
$$;

COMMENT ON FUNCTION public.user_account_is_active(uuid) IS
  'True when public.users.account_status is active. Suspended, banned, and deactivated accounts are not active.';

REVOKE ALL ON FUNCTION public.user_account_is_active(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_account_is_active(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Session revocation for an administrative disable.
-- Access tokens can remain valid until expiry; write policies still consult
-- user_account_is_active so a leftover JWT cannot keep using the marketplace.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.revoke_marketplace_sessions(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    DELETE FROM auth.sessions WHERE user_id = p_user_id;
  EXCEPTION
    WHEN undefined_table OR undefined_column THEN
      NULL;
  END;

  BEGIN
    DELETE FROM auth.refresh_tokens WHERE user_id::text = p_user_id::text;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_marketplace_sessions(uuid)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Shared marketplace projection. One row per auth user. Seller access comes
-- from users.role and seller_profiles.is_approved, the same signals the app
-- uses for Buyer/Seller mode switching.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._marketplace_user_rows()
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email text,
  username text,
  role text,
  account_status text,
  account_type text,
  created_at timestamptz,
  seller_approved boolean,
  shop_name text,
  verification_status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    u.user_id,
    COALESCE(u.full_name, '')::text,
    COALESCE(u.email, '')::text,
    COALESCE(u.username, '')::text,
    u.role::text,
    u.account_status::text,
    CASE
      WHEN u.role = 'seller'::public.user_role_enum
        OR COALESCE(sp.is_approved, false)
        THEN 'buyer_seller'
      ELSE 'buyer'
    END,
    u.created_at,
    COALESCE(sp.is_approved, false),
    NULLIF(btrim(COALESCE(sp.shop_name, '')), ''),
    v.verification_status
  FROM public.users u
  LEFT JOIN public.seller_profiles sp ON sp.seller_id = u.user_id
  LEFT JOIN LATERAL (
    SELECT uv.verification_status::text AS verification_status
    FROM public.user_verifications uv
    WHERE uv.user_id = u.user_id
      AND uv.application_type = 'seller'
    ORDER BY uv.submitted_at DESC NULLS LAST, uv.created_at DESC
    LIMIT 1
  ) v ON true
  WHERE u.role IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  );
$$;

REVOKE ALL ON FUNCTION public._marketplace_user_rows()
  FROM PUBLIC, anon, authenticated;

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

  IF v_type IS NOT NULL AND v_type NOT IN ('all', 'buyer', 'seller') THEN
    RAISE EXCEPTION 'invalid account type filter' USING ERRCODE = '22023';
  END IF;

  IF v_status IS NOT NULL AND v_status NOT IN (
    'all', 'active', 'suspended', 'banned', 'deactivated'
  ) THEN
    RAISE EXCEPTION 'invalid account status filter' USING ERRCODE = '22023';
  END IF;

  IF v_type = 'all' THEN
    v_type := NULL;
  END IF;
  IF v_status = 'all' THEN
    v_status := NULL;
  END IF;

  IF v_search IS NOT NULL THEN
    v_search := replace(v_search, chr(92), chr(92) || chr(92));
    v_search := replace(v_search, '%', chr(92) || '%');
    v_search := replace(v_search, '_', chr(92) || '_');
  END IF;

  SELECT count(*)::bigint
    INTO v_total
  FROM public._marketplace_user_rows() r
  WHERE (
      v_status IS NULL
      OR r.account_status = v_status
    )
    AND (
      v_type IS NULL
      OR (v_type = 'buyer' AND r.account_type IN ('buyer', 'buyer_seller'))
      OR (v_type = 'seller' AND r.account_type = 'buyer_seller')
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
      (r.account_status = 'active') AS can_disable
    FROM public._marketplace_user_rows() r
    WHERE (
        v_status IS NULL
        OR r.account_status = v_status
      )
      AND (
        v_type IS NULL
        OR (v_type = 'buyer' AND r.account_type IN ('buyer', 'buyer_seller'))
        OR (v_type = 'seller' AND r.account_type = 'buyer_seller')
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
    'active', count(*) FILTER (WHERE account_status = 'active'),
    'disabled', count(*) FILTER (WHERE account_status = 'suspended'),
    'banned', count(*) FILTER (WHERE account_status = 'banned')
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

REVOKE ALL ON FUNCTION public.list_marketplace_users(text, text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_marketplace_users(text, text, text, integer, integer)
  TO authenticated;

COMMENT ON FUNCTION public.list_marketplace_users(text, text, text, integer, integer) IS
  'Admin-only directory of buyer and seller accounts. Excludes admin and super_admin. Counts ignore search and filters.';

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
    'can_disable', r.account_status = 'active'
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

REVOKE ALL ON FUNCTION public.get_marketplace_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_marketplace_user(uuid) TO authenticated;

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

  PERFORM public.record_admin_audit_log(
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
      'new_status', 'suspended'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'account_status', 'suspended',
    'user_id', p_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.disable_marketplace_account(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.disable_marketplace_account(uuid, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.disable_marketplace_account(uuid, text, text) IS
  'Admin-only. Sets a buyer or seller from active to suspended, revokes sessions, and writes one audit row. Rejects admin, super admin, suspended, banned, and other non-active accounts.';

-- ---------------------------------------------------------------------------
-- Marketplace writes. Existing bid and Looking For functions already require
-- an active account. These close purchase, cart, and messaging gaps, including
-- security-definer inserts that skip RLS.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_active_buyer_on_order()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.user_account_is_active(NEW.buyer_id) THEN
    RAISE EXCEPTION 'This account cannot place orders.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_require_active_buyer ON public.orders;
CREATE TRIGGER trg_orders_require_active_buyer
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_buyer_on_order();

CREATE OR REPLACE FUNCTION public.enforce_active_account_on_cart()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.user_account_is_active(NEW.user_id) THEN
    RAISE EXCEPTION 'This account cannot update the cart.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cart_items_require_active_account ON public.cart_items;
CREATE TRIGGER trg_cart_items_require_active_account
BEFORE INSERT OR UPDATE ON public.cart_items
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_account_on_cart();

CREATE OR REPLACE FUNCTION public.enforce_active_account_on_message()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.user_account_is_active(auth.uid()) THEN
    RAISE EXCEPTION 'This account cannot send messages.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT public.user_account_is_active(NEW.sender_id) THEN
    RAISE EXCEPTION 'This account cannot send messages.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_require_active_account ON public.messages;
CREATE TRIGGER trg_messages_require_active_account
BEFORE INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_account_on_message();

CREATE OR REPLACE FUNCTION public.enforce_active_account_on_conversation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.user_account_is_active(auth.uid()) THEN
    RAISE EXCEPTION 'This account cannot start a conversation.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversations_require_active_account ON public.conversations;
CREATE TRIGGER trg_conversations_require_active_account
BEFORE INSERT ON public.conversations
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_account_on_conversation();

DROP POLICY IF EXISTS cart_items_insert_own ON public.cart_items;
CREATE POLICY cart_items_insert_own ON public.cart_items
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND public.user_account_is_active(auth.uid())
  );

DROP POLICY IF EXISTS cart_items_update_own ON public.cart_items;
CREATE POLICY cart_items_update_own ON public.cart_items
  FOR UPDATE
  USING (
    auth.uid() = user_id
    AND public.user_account_is_active(auth.uid())
  )
  WITH CHECK (
    auth.uid() = user_id
    AND public.user_account_is_active(auth.uid())
  );

DROP POLICY IF EXISTS messages_insert_sender ON public.messages;
CREATE POLICY messages_insert_sender ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND public.user_account_is_active(auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.conversation_id = messages.conversation_id
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS conversations_insert_participant ON public.conversations;
CREATE POLICY conversations_insert_participant ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (
    public.user_account_is_active(auth.uid())
    AND (auth.uid() = participant_a OR auth.uid() = participant_b)
  );

DROP POLICY IF EXISTS seller_profiles_update_own ON public.seller_profiles;
CREATE POLICY seller_profiles_update_own ON public.seller_profiles
  FOR UPDATE
  USING (
    (auth.uid() = seller_id AND public.user_account_is_active(auth.uid()))
    OR public.is_admin()
  )
  WITH CHECK (
    (auth.uid() = seller_id AND public.user_account_is_active(auth.uid()))
    OR public.is_admin()
  );
