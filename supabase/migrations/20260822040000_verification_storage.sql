INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'verification-docs',
  'verification-docs',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS verification_docs_insert_own ON storage.objects;
CREATE POLICY verification_docs_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'verification-docs'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

DROP POLICY IF EXISTS verification_docs_select_own_or_admin ON storage.objects;
CREATE POLICY verification_docs_select_own_or_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'verification-docs'
    AND (
      split_part(name, '/', 1) = auth.uid()::text
      OR public.is_admin()
    )
  );

DROP POLICY IF EXISTS verification_docs_update_own ON storage.objects;
CREATE POLICY verification_docs_update_own ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'verification-docs' AND split_part(name, '/', 1) = auth.uid()::text)
  WITH CHECK (bucket_id = 'verification-docs' AND split_part(name, '/', 1) = auth.uid()::text);

DROP POLICY IF EXISTS verification_docs_delete_own_or_admin ON storage.objects;
CREATE POLICY verification_docs_delete_own_or_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'verification-docs'
    AND (split_part(name, '/', 1) = auth.uid()::text OR public.is_admin())
  );
