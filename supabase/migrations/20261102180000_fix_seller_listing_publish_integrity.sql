-- =============================================================================
-- Migration: 20261102180000_fix_seller_listing_publish_integrity.sql
-- Purpose:
--   1. Ensure `product-images` bucket configuration (public, 5 MB limit,
--      JPEG/PNG/WebP MIME types) is applied even when the bucket row already
--      existed prior to 20261016130000.
--   2. Add missing UPDATE policy on `storage.objects` for `product-images` so
--      upserts and retries under a seller's own UID prefix succeed.
--   3. Reconcile `users.role` and `seller_profiles.is_approved` and harden
--      `public.is_approved_seller()` so approved sellers are never blocked by
--      RLS 42501 when inserting into `public.products`.
--   4. Allow sellers to delete their own `auctions` rows when `bid_count = 0`
--      so draft rollback (`_deleteDraftProduct`) and unbid auction deletion
--      succeed under `FORCE ROW LEVEL SECURITY`.
-- =============================================================================

BEGIN;

-- 1. Ensure `product-images` bucket exists with the expected constraints
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-images',
  'product-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Add missing UPDATE policy on storage.objects for `product-images`
DROP POLICY IF EXISTS "product_images_storage_update_own" ON storage.objects;
CREATE POLICY "product_images_storage_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 3. Sync `users.role = 'seller'` for any user with an approved seller_profile,
--    and ensure every `role = 'seller'` user has an approved `seller_profiles` row.
UPDATE public.users u
SET role = 'seller'::user_role_enum
FROM public.seller_profiles sp
WHERE sp.seller_id = u.user_id
  AND sp.is_approved = true
  AND u.role = 'buyer'::user_role_enum;

INSERT INTO public.seller_profiles (seller_id, shop_name, city, is_approved, approved_at)
SELECT u.user_id,
       COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.username), ''), 'Shop'),
       'General Santos City',
       true,
       now()
FROM public.users u
WHERE u.role = 'seller'::user_role_enum
  AND NOT EXISTS (
    SELECT 1
    FROM public.seller_profiles sp
    WHERE sp.seller_id = u.user_id
      AND sp.is_approved = true
  )
ON CONFLICT (seller_id) DO UPDATE
SET is_approved = true,
    approved_at = COALESCE(public.seller_profiles.approved_at, now());

-- Update `public.is_approved_seller()` to match `AuthUser.hasSellerAccess`
-- and `marketplace_user_management` seller capability rules.
CREATE OR REPLACE FUNCTION public.is_approved_seller()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.seller_profiles sp
      ON sp.seller_id = u.user_id
    WHERE u.user_id = auth.uid()
      AND u.account_status = 'active'::account_status_enum
      AND (
        u.role IN ('admin'::user_role_enum, 'super_admin'::user_role_enum)
        OR u.role = 'seller'::user_role_enum
        OR COALESCE(sp.is_approved, false) = true
      )
  );
$$;

-- 4. Allow sellers to delete their own unbid auction rows (required when
--    cascading a product delete or rolling back a draft auction listing).
DROP POLICY IF EXISTS "auctions_delete_seller_unbid" ON public.auctions;
CREATE POLICY "auctions_delete_seller_unbid"
  ON public.auctions FOR DELETE
  TO authenticated
  USING (
    COALESCE(bid_count, 0) = 0
    AND EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = auctions.product_id
        AND p.seller_id = auth.uid()
    )
  );

COMMIT;
