-- Product description length (20–2000) and product-images storage bucket policies.

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_description_len;

-- Backfill legacy rows so the CHECK can be applied (client previously allowed < 20 / > 150).
UPDATE public.products
SET description = left(btrim(description), 2000)
WHERE description IS NOT NULL
  AND char_length(btrim(description)) > 2000;

UPDATE public.products
SET description = left(
  coalesce(
    nullif(btrim(description), ''),
    nullif(btrim(name), ''),
    'ThriftLine listing'
  ),
  2000
)
WHERE description IS NULL
   OR btrim(description) = ''
   OR char_length(btrim(description)) < 20;

UPDATE public.products
SET description = left(
  btrim(description) || ' — details available from seller.',
  2000
)
WHERE description IS NOT NULL
  AND char_length(btrim(description)) < 20;

ALTER TABLE public.products
  ADD CONSTRAINT products_description_len
  CHECK (
    description IS NULL
    OR (
      char_length(btrim(description)) >= 20
      AND char_length(btrim(description)) <= 2000
    )
  );

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-images',
  'product-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS product_images_storage_insert_own ON storage.objects;
CREATE POLICY product_images_storage_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS product_images_storage_select_public ON storage.objects;
CREATE POLICY product_images_storage_select_public ON storage.objects
  FOR SELECT
  USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS product_images_storage_delete_own ON storage.objects;
CREATE POLICY product_images_storage_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
