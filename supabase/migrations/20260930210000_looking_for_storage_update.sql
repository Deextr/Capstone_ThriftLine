-- Replacing a Looking For image used to upsert the same object path.
-- storage.objects had INSERT but no UPDATE, so upsert failed.
-- The app now uploads a new object key (INSERT) and deletes the old one;
-- this policy still allows upsert if an older client retries the same path.

DROP POLICY IF EXISTS looking_for_images_update_own ON storage.objects;
CREATE POLICY looking_for_images_update_own ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'looking-for'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'looking-for'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
