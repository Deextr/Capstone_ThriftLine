-- Phase 0 / 4 of 4 — RLS policy hardening for the four core tables.
--
-- RLS was already enabled on every table; the problem is the policies themselves.
-- PERMISSIVE policies are OR'd together, so the widest one always wins. The audit
-- found three consequences:
--
--   1. public.users carried two overlapping sets of policies ("Users can read own
--      profile" + users_select_all, etc.). users_select_all USING (true) grants
--      role `public` — including anon — SELECT on every column of every user,
--      leaking email and phone_number to anyone with the anon key.
--   2. products_select_all USING (true) exposes draft and soft-deleted ('removed')
--      listings to everyone.
--   3. products_insert_own only checks auth.uid() = seller_id, so any buyer can
--      create listings. There is no seller gate at all.
--
-- Depends on 20260818010000 (is_admin, is_approved_seller) and 20260818020000
-- (column guard + seller backfill). Run last.
--
-- Idempotent. Safe to re-run.

-- ===========================================================================
-- users
-- ===========================================================================

DROP POLICY IF EXISTS "Users can read own profile"   ON public.users;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS users_select_all               ON public.users;
DROP POLICY IF EXISTS users_insert_self              ON public.users;
DROP POLICY IF EXISTS users_update_self_admin        ON public.users;
DROP POLICY IF EXISTS users_delete_admin             ON public.users;

DROP POLICY IF EXISTS users_select_self_or_admin ON public.users;
CREATE POLICY users_select_self_or_admin ON public.users
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

-- WITH CHECK is stated explicitly. The dropped users_update_self_admin omitted
-- it, which makes Postgres reuse USING as the check — easy to misread as "reads
-- are restricted but writes are open".
-- Column-level protection is the trg_users_column_guard trigger, not this policy.
DROP POLICY IF EXISTS users_update_self_or_admin ON public.users;
CREATE POLICY users_update_self_or_admin ON public.users
  FOR UPDATE
  USING      (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS users_delete_admin ON public.users;
CREATE POLICY users_delete_admin ON public.users
  FOR DELETE
  USING (public.is_admin());

-- Deliberately no INSERT policy. Rows are created solely by
-- handle_new_auth_user(), which is SECURITY DEFINER and bypasses RLS.
-- This is what makes the client-side insert in auth_service.dart redundant.

-- ---------------------------------------------------------------------------
-- Public profile projection
-- ---------------------------------------------------------------------------
-- Restricting the base table to self-or-admin removes the ability to read other
-- people's usernames, which SupabaseService.checkUsernameAvailability() needs,
-- and which seller display names will need in Phase 2. This view re-exposes only
-- the non-sensitive columns.
--
-- security_invoker = false is required, not incidental: the view must run with
-- the owner's rights so it can read past the base-table policy. Postgres has no
-- column-level RLS, so a projection view is the standard way to publish a subset
-- of columns. email, phone_number and account_status are excluded.

DROP VIEW IF EXISTS public.user_public_profiles;

CREATE VIEW public.user_public_profiles
WITH (security_invoker = false) AS
SELECT
  u.user_id,
  u.username,
  u.full_name,
  u.avatar,
  u.role,
  u.trust_score,
  u.rating_average,
  u.rating_count,
  u.created_at
FROM public.users u
WHERE u.account_status = 'active'::account_status_enum;

COMMENT ON VIEW public.user_public_profiles IS
  'Non-sensitive projection of public.users for username lookups and seller display. Excludes email, phone_number and account_status.';

GRANT SELECT ON public.user_public_profiles TO anon, authenticated;

-- ===========================================================================
-- products
-- ===========================================================================

-- 'draft' and 'removed' become owner/admin-only. 'sold' stays publicly visible
-- because buyers must still be able to open a product they have purchased, and
-- the seller Listings tab already queries status IN ('active','sold').
DROP POLICY IF EXISTS products_select_all        ON public.products;
DROP POLICY IF EXISTS products_select_visible    ON public.products;
CREATE POLICY products_select_visible ON public.products
  FOR SELECT
  USING (
    status IN ('active'::product_status_enum, 'sold'::product_status_enum)
    OR auth.uid() = seller_id
    OR public.is_admin()
  );

-- The seller gate. Previously absent entirely.
DROP POLICY IF EXISTS products_insert_own        ON public.products;
DROP POLICY IF EXISTS products_insert_own_seller ON public.products;
CREATE POLICY products_insert_own_seller ON public.products
  FOR INSERT
  WITH CHECK (auth.uid() = seller_id AND public.is_approved_seller());

-- WITH CHECK also pins seller_id so a seller cannot reassign a listing to
-- someone else. Suspended sellers lose edit rights via is_approved_seller().
DROP POLICY IF EXISTS products_update_own_admin  ON public.products;
DROP POLICY IF EXISTS products_update_own_seller ON public.products;
CREATE POLICY products_update_own_seller ON public.products
  FOR UPDATE
  USING      ((auth.uid() = seller_id AND public.is_approved_seller()) OR public.is_admin())
  WITH CHECK ((auth.uid() = seller_id AND public.is_approved_seller()) OR public.is_admin());

-- Retained as-is; the app soft-deletes via status = 'removed' rather than
-- issuing a real DELETE, but hard delete stays available to the owner.
DROP POLICY IF EXISTS products_delete_own_admin ON public.products;
CREATE POLICY products_delete_own_admin ON public.products
  FOR DELETE
  USING (auth.uid() = seller_id OR public.is_admin());

-- ===========================================================================
-- product_images
-- ===========================================================================

-- Visibility now mirrors the parent product instead of being unconditionally
-- public, so images of draft and removed listings stop being enumerable.
DROP POLICY IF EXISTS product_images_select_all     ON public.product_images;
DROP POLICY IF EXISTS product_images_select_visible ON public.product_images;
CREATE POLICY product_images_select_visible ON public.product_images
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = product_images.product_id
        AND (
          p.status IN ('active'::product_status_enum, 'sold'::product_status_enum)
          OR p.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

-- INSERT / UPDATE / DELETE already derive ownership from the parent product and
-- are correct as they stand; they are restated here so this file is a complete
-- description of the table's access rules.
DROP POLICY IF EXISTS product_images_insert_own ON public.product_images;
CREATE POLICY product_images_insert_own ON public.product_images
  FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.products p
            WHERE p.product_id = product_images.product_id
              AND p.seller_id = auth.uid())
  );

DROP POLICY IF EXISTS product_images_update_own_admin ON public.product_images;
CREATE POLICY product_images_update_own_admin ON public.product_images
  FOR UPDATE
  USING (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.products p
               WHERE p.product_id = product_images.product_id
                 AND p.seller_id = auth.uid())
  );

DROP POLICY IF EXISTS product_images_delete_own_admin ON public.product_images;
CREATE POLICY product_images_delete_own_admin ON public.product_images
  FOR DELETE
  USING (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.products p
               WHERE p.product_id = product_images.product_id
                 AND p.seller_id = auth.uid())
  );

-- ===========================================================================
-- categories
-- ===========================================================================
-- Already correct: categories_select_all USING (true) plus admin-only write.
-- Restated verbatim so this file fully documents the four core tables.

DROP POLICY IF EXISTS categories_select_all   ON public.categories;
CREATE POLICY categories_select_all ON public.categories
  FOR SELECT USING (true);

DROP POLICY IF EXISTS categories_write_admin  ON public.categories;
CREATE POLICY categories_write_admin ON public.categories
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS categories_update_admin ON public.categories;
CREATE POLICY categories_update_admin ON public.categories
  FOR UPDATE USING (public.is_admin());

DROP POLICY IF EXISTS categories_delete_admin ON public.categories;
CREATE POLICY categories_delete_admin ON public.categories
  FOR DELETE USING (public.is_admin());
