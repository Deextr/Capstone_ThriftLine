-- Optional buyer review photos (max 3 per review).

CREATE TABLE IF NOT EXISTS public.review_photos (
  review_photo_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES public.reviews (review_id) ON DELETE CASCADE,
  file_path text NOT NULL,
  display_order smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT review_photos_path_unique UNIQUE (file_path)
);

CREATE INDEX IF NOT EXISTS review_photos_review_idx
  ON public.review_photos (review_id, display_order);

ALTER TABLE public.review_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_photos FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS review_photos_select_public ON public.review_photos;
CREATE POLICY review_photos_select_public ON public.review_photos
  FOR SELECT TO anon, authenticated
  USING (true);

REVOKE ALL ON TABLE public.review_photos FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.review_photos TO anon, authenticated;
GRANT ALL ON TABLE public.review_photos TO postgres, service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'review-photos',
  'review-photos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS review_photos_insert_own ON storage.objects;
CREATE POLICY review_photos_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'review-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS review_photos_select_public ON storage.objects;
CREATE POLICY review_photos_select_public ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'review-photos');

DROP POLICY IF EXISTS review_photos_delete_own ON storage.objects;
CREATE POLICY review_photos_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'review-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE OR REPLACE FUNCTION public.attach_review_photo(
  p_review_id uuid,
  p_file_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_review public.reviews%ROWTYPE;
  v_prefix text;
  v_path text;
  v_count integer;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_path := NULLIF(btrim(COALESCE(p_file_path, '')), '');
  IF v_path IS NULL OR v_path LIKE '%..%' OR v_path LIKE '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  SELECT * INTO v_review
  FROM public.reviews
  WHERE review_id = p_review_id
  FOR UPDATE;

  IF NOT FOUND OR v_review.reviewer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Review not found.');
  END IF;

  IF v_review.created_at <= (now() - interval '24 hours') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The 24-hour edit window for this review has ended.'
    );
  END IF;

  v_prefix := v_uid::text || '/' || p_review_id::text || '/';
  IF left(v_path, char_length(v_prefix)) IS DISTINCT FROM v_prefix THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  IF lower(v_path) !~ '\.(jpe?g|png|webp)$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please upload a JPG, PNG, or WebP photo.');
  END IF;

  SELECT count(*) INTO v_count
  FROM public.review_photos rp
  WHERE rp.review_id = p_review_id;

  IF v_count >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can attach up to 3 photos.');
  END IF;

  INSERT INTO public.review_photos (review_id, file_path, display_order)
  VALUES (p_review_id, v_path, v_count)
  RETURNING review_photo_id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'review_photo_id', v_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo is already attached.');
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_review_photo(p_review_photo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.review_photos%ROWTYPE;
  v_review public.reviews%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT rp.* INTO v_row
  FROM public.review_photos rp
  WHERE rp.review_photo_id = p_review_photo_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Photo not found.');
  END IF;

  SELECT * INTO v_review
  FROM public.reviews
  WHERE review_id = v_row.review_id;

  IF v_review.reviewer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Photo not found.');
  END IF;

  IF v_review.created_at <= (now() - interval '24 hours') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The 24-hour edit window for this review has ended.'
    );
  END IF;

  DELETE FROM public.review_photos
  WHERE review_photo_id = p_review_photo_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.rollback_review_without_photos(p_review_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.review_photos rp WHERE rp.review_id = p_review_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This review already has photos attached.'
    );
  END IF;

  DELETE FROM public.reviews r
  WHERE r.review_id = p_review_id
    AND r.reviewer_id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Review not found.');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.attach_review_photo(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.attach_review_photo(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.remove_review_photo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_review_photo(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rollback_review_without_photos(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rollback_review_without_photos(uuid) TO authenticated;
