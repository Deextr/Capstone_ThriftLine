-- Public HTML used after password-reset emails. Hosted Edge Functions cannot
-- serve real HTML (gateway rewrites it to text/plain), so this page lives in
-- Storage and can run JavaScript to open thriftline://reset-password.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'app-links',
  'app-links',
  true,
  65536,
  ARRAY['text/html']
)
ON CONFLICT (id) DO UPDATE
SET public = true,
    file_size_limit = 65536,
    allowed_mime_types = ARRAY['text/html'];

DROP POLICY IF EXISTS app_links_select_public ON storage.objects;
CREATE POLICY app_links_select_public ON storage.objects
  FOR SELECT
  USING (bucket_id = 'app-links');
