-- Looking For reference images (optional) + public storage bucket.
-- Apply after 20260908010000_phase2_catalog.sql.

ALTER TABLE public.looking_for_posts
  ADD COLUMN IF NOT EXISTS reference_image_url text;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'looking-for',
  'looking-for',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS looking_for_images_insert_own ON storage.objects;
CREATE POLICY looking_for_images_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'looking-for'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS looking_for_images_select_public ON storage.objects;
CREATE POLICY looking_for_images_select_public ON storage.objects
  FOR SELECT
  USING (bucket_id = 'looking-for');

DROP POLICY IF EXISTS looking_for_images_delete_own ON storage.objects;
CREATE POLICY looking_for_images_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'looking-for'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Sellers and the post owner can already read responses. Open requests are a
-- public discussion, so authenticated users may read comments on open posts.
DROP POLICY IF EXISTS looking_for_responses_select_participant_admin
  ON public.looking_for_responses;
CREATE POLICY looking_for_responses_select_open_or_participant
  ON public.looking_for_responses
  FOR SELECT
  USING (
    public.is_admin()
    OR auth.uid() = seller_id
    OR EXISTS (
      SELECT 1
      FROM public.looking_for_posts lp
      WHERE lp.post_id = looking_for_responses.post_id
        AND (
          lp.user_id = auth.uid()
          OR lp.status = 'open'::looking_for_status_enum
        )
    )
  );
