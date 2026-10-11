-- Enforce marketplace restrictions for banned/disabled sellers and trust-level Banned.
-- Hides listings at the database layer and blocks seller/buyer interactions.
-- Depends on 20261010150000_marketplace_user_management.sql for session helpers.

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

-- ---------------------------------------------------------------------------
-- Central eligibility: public marketplace presence for a seller account.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.marketplace_seller_is_public(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    p_seller_id IS NOT NULL
    AND public.user_account_is_active(p_seller_id)
    AND NOT EXISTS (
      SELECT 1
      FROM public.users u
      WHERE u.user_id = p_seller_id
        AND u.trust_level = 'Banned'
    );
$$;

COMMENT ON FUNCTION public.marketplace_seller_is_public(uuid) IS
  'True when the seller account is active and not trust-classified as Banned. Used for public catalog, bids, and new orders.';

REVOKE ALL ON FUNCTION public.marketplace_seller_is_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketplace_seller_is_public(uuid)
  TO authenticated, service_role, anon;

-- ---------------------------------------------------------------------------
-- Pause live auctions without deleting bid history.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.pause_seller_active_auctions(p_seller_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_seller_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.auctions a
  SET status = 'cancelled'::public.auction_status_enum,
      updated_at = now()
  FROM public.products p
  WHERE p.product_id = a.product_id
    AND p.seller_id = p_seller_id
    AND a.status = 'active'::public.auction_status_enum;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.pause_seller_active_auctions(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pause_seller_active_auctions(uuid)
  TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- Trust score class Banned → administrative suspension (not permanent ban).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_trust_banned_seller_sanction(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
  v_level text;
  v_name text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT u.role, u.account_status, u.trust_level,
         COALESCE(u.full_name, u.username, u.email, 'Seller')
    INTO v_role, v_status, v_level, v_name
  FROM public.users u
  WHERE u.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND OR v_level IS DISTINCT FROM 'Banned' THEN
    RETURN;
  END IF;

  IF v_role NOT IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  ) THEN
    RETURN;
  END IF;

  PERFORM public.pause_seller_active_auctions(p_user_id);

  IF v_status = 'banned'::public.account_status_enum THEN
    PERFORM public.revoke_marketplace_sessions(p_user_id);
    RETURN;
  END IF;

  IF v_status = 'active'::public.account_status_enum THEN
    UPDATE public.users
    SET account_status = 'suspended'::public.account_status_enum
    WHERE user_id = p_user_id
      AND account_status = 'active'::public.account_status_enum;

    PERFORM public.revoke_marketplace_sessions(p_user_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_trust_banned_seller_sanction(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_trust_banned_seller_sanction(uuid)
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.trg_apply_trust_banned_sanction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.trust_level = 'Banned'
     AND (
       TG_OP = 'INSERT'
       OR OLD.trust_level IS DISTINCT FROM NEW.trust_level
     )
  THEN
    PERFORM public.apply_trust_banned_seller_sanction(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_trust_banned_sanction ON public.users;
CREATE TRIGGER trg_users_trust_banned_sanction
AFTER INSERT OR UPDATE OF trust_level ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.trg_apply_trust_banned_sanction();

-- ---------------------------------------------------------------------------
-- Public catalog RLS: hide active listings from restricted sellers.
-- Sold listings stay visible for purchase history and order context.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS products_select_visible ON public.products;
CREATE POLICY products_select_visible ON public.products
  FOR SELECT
  USING (
    (
      status = 'sold'::public.product_status_enum
      OR (
        status = 'active'::public.product_status_enum
        AND public.marketplace_seller_is_public(seller_id)
      )
    )
    OR auth.uid() = seller_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS product_images_select_visible ON public.product_images;
CREATE POLICY product_images_select_visible ON public.product_images
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = product_images.product_id
        AND (
          p.status = 'sold'::public.product_status_enum
          OR (
            p.status = 'active'::public.product_status_enum
            AND public.marketplace_seller_is_public(p.seller_id)
          )
          OR p.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

-- Looking For: hide open posts from restricted accounts.
DROP POLICY IF EXISTS looking_for_posts_select_public_or_owner ON public.looking_for_posts;
CREATE POLICY looking_for_posts_select_public_or_owner ON public.looking_for_posts
  FOR SELECT
  USING (
    public.is_admin()
    OR (
      owner_deleted_at IS NULL
      AND auth.uid() = user_id
    )
    OR (
      owner_deleted_at IS NULL
      AND moderation_removed_at IS NULL
      AND status = 'open'::public.looking_for_status_enum
      AND expires_at > now()
      AND public.user_account_is_active(user_id)
      AND NOT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.user_id = looking_for_posts.user_id
          AND u.trust_level = 'Banned'
      )
    )
  );

-- New orders cannot target a restricted seller.
CREATE OR REPLACE FUNCTION public.enforce_public_seller_on_order()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.seller_id IS NOT NULL
     AND NOT public.marketplace_seller_is_public(NEW.seller_id) THEN
    RAISE EXCEPTION
      'This listing is no longer available from this seller.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_require_public_seller ON public.orders;
CREATE TRIGGER trg_orders_require_public_seller
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.enforce_public_seller_on_order();

-- Account status transitions: pause live auctions for sellers.
CREATE OR REPLACE FUNCTION public.enforce_seller_restriction_side_effects()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.account_status IS DISTINCT FROM OLD.account_status
     AND NEW.account_status IN (
       'suspended'::public.account_status_enum,
       'banned'::public.account_status_enum,
       'deactivated'::public.account_status_enum
     )
     AND OLD.account_status = 'active'::public.account_status_enum
     AND NEW.role IN (
       'buyer'::public.user_role_enum,
       'seller'::public.user_role_enum
     )
  THEN
    PERFORM public.pause_seller_active_auctions(NEW.user_id);
    IF NEW.account_status IN (
      'suspended'::public.account_status_enum,
      'banned'::public.account_status_enum
    ) THEN
      PERFORM public.revoke_marketplace_sessions(NEW.user_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_marketplace_restriction_effects ON public.users;
CREATE TRIGGER trg_users_marketplace_restriction_effects
AFTER UPDATE OF account_status ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.enforce_seller_restriction_side_effects();

-- Block new bids when the listing seller is restricted (place_bid inserts bids).
CREATE OR REPLACE FUNCTION public.enforce_bid_on_public_seller_auction()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_seller_id uuid;
BEGIN
  SELECT p.seller_id
    INTO v_seller_id
  FROM public.auctions a
  JOIN public.products p ON p.product_id = a.product_id
  WHERE a.auction_id = NEW.auction_id;

  IF v_seller_id IS NULL
     OR NOT public.marketplace_seller_is_public(v_seller_id) THEN
    RAISE EXCEPTION 'This listing is no longer available.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bids_public_seller_auction ON public.bids;
CREATE TRIGGER trg_bids_public_seller_auction
BEFORE INSERT ON public.bids
FOR EACH ROW
EXECUTE FUNCTION public.enforce_bid_on_public_seller_auction();

-- Admin directory: expose trust_level and effective disable eligibility.
-- Return type adds trust columns; REPLACE cannot alter OUT parameters.
DROP FUNCTION IF EXISTS public._marketplace_user_rows();

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
  verification_status text,
  trust_level text,
  trust_score numeric
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
    v.verification_status,
    u.trust_level,
    u.trust_score
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

CREATE OR REPLACE FUNCTION public.marketplace_effective_account_status(
  p_account_status text,
  p_trust_level text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN lower(btrim(COALESCE(p_account_status, ''))) = 'banned'
      OR btrim(COALESCE(p_trust_level, '')) = 'Banned'
      THEN 'banned'
    ELSE lower(btrim(COALESCE(p_account_status, 'active')))
  END;
$$;

-- Backfill: trust-classified Banned sellers still marked active.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT u.user_id
    FROM public.users u
    WHERE u.trust_level = 'Banned'
      AND u.role IN ('buyer'::public.user_role_enum, 'seller'::public.user_role_enum)
  LOOP
    PERFORM public.apply_trust_banned_seller_sanction(r.user_id);
  END LOOP;
END;
$$;
