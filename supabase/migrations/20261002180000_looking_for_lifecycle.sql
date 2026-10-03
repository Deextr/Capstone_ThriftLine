-- Looking For lifecycle, abuse limits, reports, and strikes.
--
-- Active means status = open, expires_at is still in the future, and the
-- request was not removed by moderation or deleted by its owner.
-- Expiration is expires_at <= now(). It is not a new status and not a strike.
-- Moderation removal is moderation_removed_at. Owner cleanup is owner_deleted_at.
-- Clients cannot insert, update, or delete looking_for_posts directly.

-- ---------------------------------------------------------------------------
-- Text matching. pg_trgm is not installed in this project; the comparison
-- below is the one implementation both SQL and the Dart tests follow.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_looking_for_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT regexp_replace(
    regexp_replace(lower(btrim(COALESCE(p_text, ''))), '[^a-z0-9[:space:]]', '', 'g'),
    '[[:space:]]+',
    ' ',
    'g'
  );
$$;

CREATE OR REPLACE FUNCTION public.looking_for_content_tokens(p_text text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(array_agg(DISTINCT tok), ARRAY[]::text[])
  FROM regexp_split_to_table(public.normalize_looking_for_text(p_text), ' ') AS tok
  WHERE char_length(tok) > 0
    AND NOT (tok = ANY (ARRAY[
      'looking','for','a','an','the','need','needed','want','wanted',
      'i','im','my','please','find','searching','search','iso','anyone',
      'have','has','with','and','or','of','to','me','some','buy','buying'
    ]::text[]));
$$;

CREATE OR REPLACE FUNCTION public.looking_for_trigrams(p_text text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  WITH padded AS (
    SELECT '  ' || public.normalize_looking_for_text(p_text) || ' ' AS s
  )
  SELECT COALESCE(array_agg(DISTINCT gram), ARRAY[]::text[])
  FROM (
    SELECT substr(s, i, 3) AS gram
    FROM padded
    CROSS JOIN LATERAL generate_series(1, GREATEST(char_length(s) - 2, 0)) AS i
  ) grams
  WHERE char_length(gram) = 3;
$$;

CREATE OR REPLACE FUNCTION public.looking_for_trigram_similarity(p_left text, p_right text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_left text[] := public.looking_for_trigrams(p_left);
  v_right text[] := public.looking_for_trigrams(p_right);
  v_shared integer;
  v_union integer;
BEGIN
  IF cardinality(v_left) = 0 OR cardinality(v_right) = 0 THEN
    RETURN 0;
  END IF;
  SELECT count(*) INTO v_shared
  FROM (
    SELECT unnest(v_left)
    INTERSECT
    SELECT unnest(v_right)
  ) shared;
  SELECT count(*) INTO v_union
  FROM (
    SELECT unnest(v_left)
    UNION
    SELECT unnest(v_right)
  ) united;
  IF v_union = 0 THEN
    RETURN 0;
  END IF;
  RETURN v_shared::numeric / v_union::numeric;
END;
$$;

CREATE OR REPLACE FUNCTION public.looking_for_is_near_duplicate(p_left text, p_right text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_left text := public.normalize_looking_for_text(p_left);
  v_right text := public.normalize_looking_for_text(p_right);
  v_left_tokens text[];
  v_right_tokens text[];
  v_shared integer;
  v_union integer;
  v_jaccard numeric;
BEGIN
  IF v_left = '' OR v_right = '' THEN
    RETURN false;
  END IF;
  IF v_left = v_right THEN
    RETURN true;
  END IF;

  v_left_tokens := public.looking_for_content_tokens(v_left);
  v_right_tokens := public.looking_for_content_tokens(v_right);
  IF cardinality(v_left_tokens) = 0 OR cardinality(v_right_tokens) = 0 THEN
    RETURN false;
  END IF;

  SELECT count(*) INTO v_shared
  FROM (
    SELECT unnest(v_left_tokens)
    INTERSECT
    SELECT unnest(v_right_tokens)
  ) shared;
  SELECT count(*) INTO v_union
  FROM (
    SELECT unnest(v_left_tokens)
    UNION
    SELECT unnest(v_right_tokens)
  ) united;
  IF v_union = 0 THEN
    RETURN false;
  END IF;

  v_jaccard := v_shared::numeric / v_union::numeric;
  IF v_jaccard >= 0.74 AND v_shared >= 3 THEN
    RETURN true;
  END IF;
  IF v_jaccard >= 0.85 AND v_shared >= 2 THEN
    RETURN true;
  END IF;
  IF v_shared >= 2 AND public.looking_for_trigram_similarity(v_left, v_right) >= 0.9 THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.looking_for_expires_at(p_from timestamptz)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT p_from + interval '3 days';
$$;

-- ---------------------------------------------------------------------------
-- Posts
-- ---------------------------------------------------------------------------

ALTER TABLE public.looking_for_posts
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS title_normalized text,
  ADD COLUMN IF NOT EXISTS reposted_from_post_id uuid,
  ADD COLUMN IF NOT EXISTS moderation_removed_at timestamptz,
  ADD COLUMN IF NOT EXISTS owner_deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS expiry_notified_at timestamptz;

UPDATE public.looking_for_posts
SET expires_at = public.looking_for_expires_at(created_at)
WHERE expires_at IS NULL;

UPDATE public.looking_for_posts
SET title_normalized = public.normalize_looking_for_text(title)
WHERE title_normalized IS NULL;

ALTER TABLE public.looking_for_posts
  ALTER COLUMN expires_at SET NOT NULL,
  ALTER COLUMN expires_at SET DEFAULT (now() + interval '3 days');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'looking_for_posts_reposted_from_fkey'
      AND conrelid = 'public.looking_for_posts'::regclass
  ) THEN
    ALTER TABLE public.looking_for_posts
      ADD CONSTRAINT looking_for_posts_reposted_from_fkey
      FOREIGN KEY (reposted_from_post_id)
      REFERENCES public.looking_for_posts (post_id)
      ON DELETE SET NULL;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS looking_for_posts_user_expires_idx
  ON public.looking_for_posts (user_id, expires_at DESC);

CREATE INDEX IF NOT EXISTS looking_for_posts_public_active_idx
  ON public.looking_for_posts (created_at DESC)
  WHERE status = 'open'
    AND moderation_removed_at IS NULL
    AND owner_deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.enforce_looking_for_post_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.title_normalized := public.normalize_looking_for_text(NEW.title);

  IF current_setting('thriftline.lf_write', true) IS DISTINCT FROM '1' THEN
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'Looking For requests are created by ThriftLine.'
        USING ERRCODE = '42501';
    END IF;
    NEW.user_id := OLD.user_id;
    NEW.expires_at := OLD.expires_at;
    NEW.created_at := OLD.created_at;
    NEW.moderation_removed_at := OLD.moderation_removed_at;
    NEW.owner_deleted_at := OLD.owner_deleted_at;
    NEW.reposted_from_post_id := OLD.reposted_from_post_id;
    NEW.expiry_notified_at := OLD.expiry_notified_at;
    NEW.status := OLD.status;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    NEW.expires_at := public.looking_for_expires_at(now());
    NEW.moderation_removed_at := NULL;
    NEW.owner_deleted_at := NULL;
    NEW.expiry_notified_at := NULL;
    NEW.status := 'open'::public.looking_for_status_enum;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_looking_for_posts_guard ON public.looking_for_posts;
CREATE TRIGGER trg_looking_for_posts_guard
BEFORE INSERT OR UPDATE ON public.looking_for_posts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_looking_for_post_guard();

DROP POLICY IF EXISTS looking_for_posts_select_all ON public.looking_for_posts;
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
    )
  );

DROP POLICY IF EXISTS looking_for_posts_insert_own ON public.looking_for_posts;
DROP POLICY IF EXISTS looking_for_posts_update_own_admin ON public.looking_for_posts;
DROP POLICY IF EXISTS looking_for_posts_delete_own_admin ON public.looking_for_posts;

REVOKE INSERT, UPDATE, DELETE ON public.looking_for_posts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.looking_for_posts TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Rate-limit ledger. Rows stay after the buyer deletes a request.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.looking_for_post_activity (
  activity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  post_id uuid NOT NULL REFERENCES public.looking_for_posts (post_id) ON DELETE RESTRICT,
  event_type text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT looking_for_post_activity_type_check
    CHECK (event_type IN ('create', 'repost'))
);

CREATE INDEX IF NOT EXISTS looking_for_post_activity_user_created_idx
  ON public.looking_for_post_activity (user_id, created_at DESC);

ALTER TABLE public.looking_for_post_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_post_activity FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.looking_for_post_activity FROM PUBLIC, anon, authenticated;

INSERT INTO public.looking_for_post_activity (user_id, post_id, event_type, created_at)
SELECT p.user_id, p.post_id, 'create', p.created_at
FROM public.looking_for_posts p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.looking_for_post_activity a
  WHERE a.post_id = p.post_id
);

-- ---------------------------------------------------------------------------
-- Reports, confirmed offenses, and posting restrictions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.looking_for_reports (
  report_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.looking_for_posts (post_id) ON DELETE RESTRICT,
  reporter_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  reported_user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  reason text NOT NULL,
  details text,
  status public.report_status_enum NOT NULL DEFAULT 'under_review',
  reviewed_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT looking_for_reports_reason_check CHECK (reason IN (
    'spam',
    'unrelated_content',
    'inappropriate_content',
    'scam_or_suspicious',
    'other'
  )),
  CONSTRAINT looking_for_reports_details_len CHECK (
    details IS NULL OR char_length(details) <= 400
  ),
  CONSTRAINT looking_for_reports_other_details CHECK (
    reason <> 'other' OR char_length(btrim(COALESCE(details, ''))) >= 8
  ),
  CONSTRAINT looking_for_reports_not_self CHECK (reporter_id <> reported_user_id),
  CONSTRAINT looking_for_reports_once UNIQUE (post_id, reporter_id)
);

CREATE INDEX IF NOT EXISTS looking_for_reports_status_created_idx
  ON public.looking_for_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS looking_for_reports_reported_idx
  ON public.looking_for_reports (reported_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS looking_for_reports_reporter_created_idx
  ON public.looking_for_reports (reporter_id, created_at DESC);

ALTER TABLE public.looking_for_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_reports FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS looking_for_reports_select_reporter_or_admin
  ON public.looking_for_reports;
CREATE POLICY looking_for_reports_select_reporter_or_admin
  ON public.looking_for_reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid() OR public.is_admin());

REVOKE ALL ON public.looking_for_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.looking_for_reports TO authenticated;

CREATE TABLE IF NOT EXISTS public.looking_for_violations (
  violation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  post_id uuid NOT NULL REFERENCES public.looking_for_posts (post_id) ON DELETE RESTRICT,
  report_id uuid NOT NULL UNIQUE REFERENCES public.looking_for_reports (report_id) ON DELETE RESTRICT,
  strike_number integer NOT NULL CHECK (strike_number >= 1),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS looking_for_violations_post_once
  ON public.looking_for_violations (post_id);

CREATE INDEX IF NOT EXISTS looking_for_violations_user_created_idx
  ON public.looking_for_violations (user_id, created_at DESC);

ALTER TABLE public.looking_for_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_violations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS looking_for_violations_select_admin
  ON public.looking_for_violations;
CREATE POLICY looking_for_violations_select_admin
  ON public.looking_for_violations
  FOR SELECT TO authenticated
  USING (public.is_admin());

REVOKE ALL ON public.looking_for_violations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.looking_for_violations TO authenticated;

CREATE TABLE IF NOT EXISTS public.looking_for_account_sanctions (
  user_id uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE RESTRICT,
  strike_count integer NOT NULL DEFAULT 0 CHECK (strike_count >= 0),
  restricted_until timestamptz,
  permanently_disabled_at timestamptz,
  disable_reason text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.looking_for_account_sanctions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_account_sanctions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS looking_for_sanctions_select_own_or_admin
  ON public.looking_for_account_sanctions;
CREATE POLICY looking_for_sanctions_select_own_or_admin
  ON public.looking_for_account_sanctions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

REVOKE ALL ON public.looking_for_account_sanctions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.looking_for_account_sanctions TO authenticated;

-- Once a Looking For strike disables an account, a normal profile update
-- cannot turn it back on. This runs after the users column guard.
CREATE OR REPLACE FUNCTION public.enforce_lf_permanent_disable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.looking_for_account_sanctions s
    WHERE s.user_id = NEW.user_id
      AND s.permanently_disabled_at IS NOT NULL
  ) THEN
    NEW.account_status := 'banned'::public.account_status_enum;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_lf_permanent_disable ON public.users;
CREATE TRIGGER trg_users_lf_permanent_disable
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.enforce_lf_permanent_disable();

CREATE OR REPLACE VIEW public.admin_looking_for_report_queue
WITH (security_invoker = true) AS
SELECT
  r.report_id,
  r.post_id,
  r.reason,
  r.details,
  r.status,
  r.created_at,
  r.resolved_at,
  r.reporter_id,
  r.reported_user_id,
  p.title AS post_title,
  p.description AS post_description,
  p.reference_image_url,
  p.created_at AS post_created_at,
  p.expires_at,
  p.status AS post_status,
  p.moderation_removed_at,
  p.owner_deleted_at,
  ru.username AS reporter_username,
  ru.full_name AS reporter_name,
  ru.role::text AS reporter_role,
  du.username AS reported_username,
  du.full_name AS reported_name,
  du.role::text AS reported_role,
  du.account_status::text AS reported_account_status,
  (
    SELECT count(*)::integer
    FROM public.looking_for_violations v
    WHERE v.user_id = r.reported_user_id
  ) AS confirmed_violations
FROM public.looking_for_reports r
JOIN public.looking_for_posts p ON p.post_id = r.post_id
JOIN public.users ru ON ru.user_id = r.reporter_id
JOIN public.users du ON du.user_id = r.reported_user_id;

CREATE OR REPLACE VIEW public.admin_disabled_accounts
WITH (security_invoker = true) AS
SELECT
  s.user_id,
  s.strike_count,
  s.permanently_disabled_at,
  s.disable_reason,
  s.restricted_until,
  u.username,
  u.full_name,
  u.role::text AS role,
  u.account_status::text AS account_status
FROM public.looking_for_account_sanctions s
JOIN public.users u ON u.user_id = s.user_id
WHERE s.permanently_disabled_at IS NOT NULL;

GRANT SELECT ON public.admin_looking_for_report_queue TO authenticated;
GRANT SELECT ON public.admin_disabled_accounts TO authenticated;

-- ---------------------------------------------------------------------------
-- Shared checks
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.looking_for_fail(p_error text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('success', false, 'error', p_error);
$$;

CREATE OR REPLACE FUNCTION public.looking_for_posting_block(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status public.account_status_enum;
  v_until timestamptz;
  v_disabled timestamptz;
  v_recent integer;
  v_last timestamptz;
BEGIN
  SELECT u.account_status
  INTO v_status
  FROM public.users u
  WHERE u.user_id = p_user_id;

  IF v_status IS NULL THEN
    RETURN 'Please sign in to post a request.';
  END IF;
  IF v_status <> 'active'::public.account_status_enum THEN
    RETURN 'This account has been permanently disabled.';
  END IF;

  SELECT s.restricted_until, s.permanently_disabled_at
  INTO v_until, v_disabled
  FROM public.looking_for_account_sanctions s
  WHERE s.user_id = p_user_id;

  IF v_disabled IS NOT NULL THEN
    RETURN 'This account has been permanently disabled.';
  END IF;
  IF v_until IS NOT NULL AND v_until > now() THEN
    RETURN 'You can''t post Looking For requests until '
      || to_char(v_until AT TIME ZONE 'Asia/Manila', 'Mon DD, HH12:MI AM')
      || '.';
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.looking_for_post_activity a
  WHERE a.user_id = p_user_id
    AND a.created_at >= now() - interval '24 hours';

  IF v_recent >= 5 THEN
    RETURN 'You can post up to 5 Looking For requests in 24 hours.';
  END IF;

  SELECT max(a.created_at) INTO v_last
  FROM public.looking_for_post_activity a
  WHERE a.user_id = p_user_id;

  IF v_last IS NOT NULL AND v_last > now() - interval '45 seconds' THEN
    RETURN 'Please wait a moment before posting another request.';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.looking_for_posting_block(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.looking_for_image_url_ok(p_user_id uuid, p_url text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_url IS NULL OR btrim(p_url) = '' THEN
    RETURN true;
  END IF;
  IF char_length(p_url) > 2000 THEN
    RETURN false;
  END IF;
  RETURN position(
    ('/object/public/looking-for/' || p_user_id::text || '/') in p_url
  ) > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.looking_for_has_active_duplicate(
  p_user_id uuid,
  p_title text,
  p_exclude uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.looking_for_posts p
    WHERE p.user_id = p_user_id
      AND p.owner_deleted_at IS NULL
      AND p.moderation_removed_at IS NULL
      AND p.status = 'open'::public.looking_for_status_enum
      AND p.expires_at > now()
      AND (p_exclude IS NULL OR p.post_id <> p_exclude)
      AND public.looking_for_is_near_duplicate(p.title, p_title)
  );
$$;

CREATE OR REPLACE FUNCTION public._looking_for_validate_content(
  p_title text,
  p_description text,
  p_budget_min numeric,
  p_budget_max numeric,
  p_size text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_title text := btrim(COALESCE(p_title, ''));
  v_description text := btrim(COALESCE(p_description, ''));
BEGIN
  IF char_length(v_title) < 3 THEN
    RETURN 'Please enter what you are looking for.';
  END IF;
  IF char_length(v_title) > 140 THEN
    RETURN 'Keep the request title under 140 characters.';
  END IF;
  IF char_length(v_description) > 2000 THEN
    RETURN 'Keep the description under 2,000 characters.';
  END IF;
  IF p_budget_min < 0 OR p_budget_max < 0 THEN
    RETURN 'Enter a budget of zero or more.';
  END IF;
  IF p_budget_max < p_budget_min THEN
    RETURN 'The maximum budget must be at least the minimum.';
  END IF;
  IF p_budget_max > 10000000 THEN
    RETURN 'Enter a smaller budget.';
  END IF;
  IF p_size IS NOT NULL AND char_length(btrim(p_size)) > 40 THEN
    RETURN 'Keep the size under 40 characters.';
  END IF;
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- Create, update, delete, repost
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_looking_for_request(
  p_title text,
  p_description text DEFAULT '',
  p_category_name text DEFAULT NULL,
  p_budget_min numeric DEFAULT 0,
  p_budget_max numeric DEFAULT 0,
  p_size text DEFAULT NULL,
  p_image_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_block text;
  v_content text;
  v_category uuid;
  v_post_id uuid;
  v_size text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to post a request.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('lf:' || v_uid::text));

  v_block := public.looking_for_posting_block(v_uid);
  IF v_block IS NOT NULL THEN
    RETURN public.looking_for_fail(v_block);
  END IF;

  v_content := public._looking_for_validate_content(
    p_title, p_description, COALESCE(p_budget_min, 0), COALESCE(p_budget_max, 0), p_size
  );
  IF v_content IS NOT NULL THEN
    RETURN public.looking_for_fail(v_content);
  END IF;

  IF NOT public.looking_for_image_url_ok(v_uid, NULLIF(btrim(COALESCE(p_image_url, '')), '')) THEN
    RETURN public.looking_for_fail('That image cannot be attached to this request.');
  END IF;

  IF public.looking_for_has_active_duplicate(v_uid, p_title, NULL) THEN
    RETURN public.looking_for_fail(
      'You already have an active request like this. Wait until it expires or edit that request.'
    );
  END IF;

  IF NULLIF(btrim(COALESCE(p_category_name, '')), '') IS NOT NULL THEN
    SELECT c.category_id INTO v_category
    FROM public.categories c
    WHERE c.category_name ILIKE btrim(p_category_name)
    LIMIT 1;
  END IF;

  v_size := NULLIF(btrim(COALESCE(p_size, '')), '');
  v_post_id := gen_random_uuid();

  PERFORM set_config('thriftline.lf_write', '1', true);
  INSERT INTO public.looking_for_posts (
    post_id,
    user_id,
    title,
    description,
    preferred_size,
    minimum_price,
    maximum_price,
    category_id,
    status,
    reference_image_url
  ) VALUES (
    v_post_id,
    v_uid,
    btrim(p_title),
    btrim(COALESCE(p_description, '')),
    v_size,
    COALESCE(p_budget_min, 0),
    COALESCE(p_budget_max, 0),
    v_category,
    'open',
    NULLIF(btrim(COALESCE(p_image_url, '')), '')
  );

  INSERT INTO public.looking_for_post_activity (user_id, post_id, event_type)
  VALUES (v_uid, v_post_id, 'create');

  RETURN jsonb_build_object('success', true, 'post_id', v_post_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_looking_for_request(
  p_post_id uuid,
  p_title text,
  p_description text DEFAULT '',
  p_category_name text DEFAULT NULL,
  p_budget_min numeric DEFAULT 0,
  p_budget_max numeric DEFAULT 0,
  p_size text DEFAULT NULL,
  p_image_url text DEFAULT NULL,
  p_clear_image boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_post public.looking_for_posts%ROWTYPE;
  v_content text;
  v_category uuid;
  v_image text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to edit this request.');
  END IF;

  SELECT * INTO v_post
  FROM public.looking_for_posts
  WHERE post_id = p_post_id;

  IF NOT FOUND OR v_post.user_id <> v_uid THEN
    RETURN public.looking_for_fail('That request could not be updated.');
  END IF;
  IF v_post.owner_deleted_at IS NOT NULL OR v_post.moderation_removed_at IS NOT NULL THEN
    RETURN public.looking_for_fail('That request can no longer be edited.');
  END IF;
  IF v_post.status <> 'open'::public.looking_for_status_enum
     OR v_post.expires_at <= now() THEN
    RETURN public.looking_for_fail(
      'This request has expired. Repost it from Inactive Requests.'
    );
  END IF;

  v_content := public._looking_for_validate_content(
    p_title, p_description, COALESCE(p_budget_min, 0), COALESCE(p_budget_max, 0), p_size
  );
  IF v_content IS NOT NULL THEN
    RETURN public.looking_for_fail(v_content);
  END IF;

  IF public.looking_for_has_active_duplicate(v_uid, p_title, p_post_id) THEN
    RETURN public.looking_for_fail(
      'You already have an active request like this.'
    );
  END IF;

  v_image := v_post.reference_image_url;
  IF p_clear_image THEN
    v_image := NULL;
  END IF;
  IF NULLIF(btrim(COALESCE(p_image_url, '')), '') IS NOT NULL THEN
    IF NOT public.looking_for_image_url_ok(v_uid, p_image_url) THEN
      RETURN public.looking_for_fail('That image cannot be attached to this request.');
    END IF;
    v_image := btrim(p_image_url);
  END IF;

  v_category := v_post.category_id;
  IF NULLIF(btrim(COALESCE(p_category_name, '')), '') IS NOT NULL THEN
    SELECT c.category_id INTO v_category
    FROM public.categories c
    WHERE c.category_name ILIKE btrim(p_category_name)
    LIMIT 1;
    v_category := COALESCE(v_category, v_post.category_id);
  END IF;

  PERFORM set_config('thriftline.lf_write', '1', true);
  UPDATE public.looking_for_posts
  SET
    title = btrim(p_title),
    description = btrim(COALESCE(p_description, '')),
    preferred_size = NULLIF(btrim(COALESCE(p_size, '')), ''),
    minimum_price = COALESCE(p_budget_min, 0),
    maximum_price = COALESCE(p_budget_max, 0),
    category_id = v_category,
    reference_image_url = v_image
  WHERE post_id = p_post_id
    AND user_id = v_uid;

  RETURN jsonb_build_object('success', true, 'post_id', p_post_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_looking_for_request(p_post_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_post public.looking_for_posts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to delete this request.');
  END IF;

  SELECT * INTO v_post
  FROM public.looking_for_posts
  WHERE post_id = p_post_id;

  IF NOT FOUND OR v_post.user_id <> v_uid THEN
    RETURN public.looking_for_fail('That request could not be deleted.');
  END IF;
  IF v_post.moderation_removed_at IS NOT NULL THEN
    RETURN public.looking_for_fail(
      'This request was removed by ThriftLine and stays on record.'
    );
  END IF;
  IF v_post.owner_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'post_id', p_post_id);
  END IF;

  PERFORM set_config('thriftline.lf_write', '1', true);
  UPDATE public.looking_for_posts
  SET owner_deleted_at = now()
  WHERE post_id = p_post_id
    AND user_id = v_uid;

  RETURN jsonb_build_object('success', true, 'post_id', p_post_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.repost_looking_for_request(
  p_post_id uuid,
  p_title text,
  p_description text DEFAULT '',
  p_category_name text DEFAULT NULL,
  p_budget_min numeric DEFAULT 0,
  p_budget_max numeric DEFAULT 0,
  p_size text DEFAULT NULL,
  p_image_url text DEFAULT NULL,
  p_clear_image boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_source public.looking_for_posts%ROWTYPE;
  v_block text;
  v_content text;
  v_category uuid;
  v_post_id uuid;
  v_image text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to repost this request.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('lf:' || v_uid::text));

  SELECT * INTO v_source
  FROM public.looking_for_posts
  WHERE post_id = p_post_id;

  IF NOT FOUND OR v_source.user_id <> v_uid OR v_source.owner_deleted_at IS NOT NULL THEN
    RETURN public.looking_for_fail('That request cannot be reposted.');
  END IF;
  IF v_source.moderation_removed_at IS NOT NULL THEN
    RETURN public.looking_for_fail(
      'This request was removed by ThriftLine and cannot be reposted.'
    );
  END IF;
  IF v_source.status <> 'open'::public.looking_for_status_enum
     OR v_source.expires_at > now() THEN
    RETURN public.looking_for_fail(
      'Only an expired request can be reposted.'
    );
  END IF;

  v_block := public.looking_for_posting_block(v_uid);
  IF v_block IS NOT NULL THEN
    RETURN public.looking_for_fail(v_block);
  END IF;

  v_content := public._looking_for_validate_content(
    p_title, p_description, COALESCE(p_budget_min, 0), COALESCE(p_budget_max, 0), p_size
  );
  IF v_content IS NOT NULL THEN
    RETURN public.looking_for_fail(v_content);
  END IF;

  v_image := NULLIF(btrim(COALESCE(p_image_url, '')), '');
  IF v_image IS NULL AND NOT COALESCE(p_clear_image, false) THEN
    v_image := v_source.reference_image_url;
  END IF;
  IF NOT public.looking_for_image_url_ok(v_uid, v_image) THEN
    RETURN public.looking_for_fail('That image cannot be attached to this request.');
  END IF;

  -- The expired source is excluded. Any other live copy still blocks the repost.
  IF public.looking_for_has_active_duplicate(v_uid, p_title, p_post_id) THEN
    RETURN public.looking_for_fail(
      'You already have an active request like this.'
    );
  END IF;

  IF NULLIF(btrim(COALESCE(p_category_name, '')), '') IS NOT NULL THEN
    SELECT c.category_id INTO v_category
    FROM public.categories c
    WHERE c.category_name ILIKE btrim(p_category_name)
    LIMIT 1;
  END IF;

  v_post_id := gen_random_uuid();
  PERFORM set_config('thriftline.lf_write', '1', true);
  INSERT INTO public.looking_for_posts (
    post_id,
    user_id,
    title,
    description,
    preferred_size,
    minimum_price,
    maximum_price,
    category_id,
    status,
    reference_image_url,
    reposted_from_post_id
  ) VALUES (
    v_post_id,
    v_uid,
    btrim(p_title),
    btrim(COALESCE(p_description, '')),
    NULLIF(btrim(COALESCE(p_size, '')), ''),
    COALESCE(p_budget_min, 0),
    COALESCE(p_budget_max, 0),
    v_category,
    'open',
    v_image,
    p_post_id
  );

  INSERT INTO public.looking_for_post_activity (user_id, post_id, event_type)
  VALUES (v_uid, v_post_id, 'repost');

  RETURN jsonb_build_object('success', true, 'post_id', v_post_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Reports and admin decisions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.report_looking_for_request(
  p_post_id uuid,
  p_reason text,
  p_details text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := lower(btrim(COALESCE(p_reason, '')));
  v_details text := NULLIF(btrim(COALESCE(p_details, '')), '');
  v_owner uuid;
  v_status public.account_status_enum;
  v_recent integer;
  v_last timestamptz;
  v_report_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN public.looking_for_fail('Please sign in to report this request.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('lf-report:' || v_uid::text));

  SELECT u.account_status INTO v_status
  FROM public.users u
  WHERE u.user_id = v_uid;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RETURN public.looking_for_fail('This account cannot submit reports.');
  END IF;

  IF v_reason NOT IN (
    'spam',
    'unrelated_content',
    'inappropriate_content',
    'scam_or_suspicious',
    'other'
  ) THEN
    RETURN public.looking_for_fail('Choose a reason for this report.');
  END IF;

  IF v_reason = 'other' AND char_length(COALESCE(v_details, '')) < 8 THEN
    RETURN public.looking_for_fail('Add a short explanation for Other.');
  END IF;
  IF char_length(COALESCE(v_details, '')) > 400 THEN
    RETURN public.looking_for_fail('Keep the explanation under 400 characters.');
  END IF;

  SELECT p.user_id INTO v_owner
  FROM public.looking_for_posts p
  WHERE p.post_id = p_post_id
    AND p.owner_deleted_at IS NULL;

  IF v_owner IS NULL THEN
    RETURN public.looking_for_fail('That request is no longer available.');
  END IF;
  IF v_owner = v_uid THEN
    RETURN public.looking_for_fail('You cannot report your own request.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.looking_for_reports r
    WHERE r.post_id = p_post_id
      AND r.reporter_id = v_uid
  ) THEN
    RETURN public.looking_for_fail('You already reported this request.');
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.looking_for_reports r
  WHERE r.reporter_id = v_uid
    AND r.created_at >= now() - interval '24 hours';
  IF v_recent >= 10 THEN
    RETURN public.looking_for_fail('You have reported enough requests for today.');
  END IF;

  SELECT max(r.created_at) INTO v_last
  FROM public.looking_for_reports r
  WHERE r.reporter_id = v_uid;
  IF v_last IS NOT NULL AND v_last > now() - interval '20 seconds' THEN
    RETURN public.looking_for_fail('Please wait a moment before sending another report.');
  END IF;

  BEGIN
    INSERT INTO public.looking_for_reports (
      post_id,
      reporter_id,
      reported_user_id,
      reason,
      details
    ) VALUES (
      p_post_id,
      v_uid,
      v_owner,
      v_reason,
      v_details
    )
    RETURNING report_id INTO v_report_id;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN public.looking_for_fail('You already reported this request.');
  END;

  RETURN jsonb_build_object('success', true, 'report_id', v_report_id);
END;
$$;

CREATE OR REPLACE FUNCTION public._looking_for_disable_auth_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  UPDATE auth.users
  SET banned_until = 'infinity'
  WHERE id = p_user_id;
EXCEPTION
  WHEN undefined_column OR undefined_table THEN
    NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._looking_for_drop_auth_sessions(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  DELETE FROM auth.sessions WHERE user_id = p_user_id;
EXCEPTION
  WHEN undefined_table OR undefined_column THEN
    NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_looking_for_report(
  p_report_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text := lower(btrim(COALESCE(p_decision, '')));
  v_report public.looking_for_reports%ROWTYPE;
  v_count integer;
  v_title text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN public.looking_for_fail('Only an admin can review this report.');
  END IF;
  IF v_decision NOT IN ('confirmed', 'dismissed') THEN
    RETURN public.looking_for_fail('Choose confirmed or dismissed.');
  END IF;

  SELECT * INTO v_report
  FROM public.looking_for_reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.looking_for_fail('That report was not found.');
  END IF;
  IF v_report.status <> 'under_review'::public.report_status_enum THEN
    RETURN public.looking_for_fail('This report has already been reviewed.');
  END IF;

  IF v_decision = 'dismissed' THEN
    UPDATE public.looking_for_reports
    SET
      status = 'dismissed'::public.report_status_enum,
      reviewed_by = v_uid,
      resolved_at = now()
    WHERE report_id = p_report_id;

    PERFORM public.notify_user(
      v_report.reporter_id,
      'system',
      'Report reviewed',
      'We reviewed your Looking For report. No violation was confirmed.',
      jsonb_build_object('report_id', p_report_id, 'status', 'dismissed')
    );

    RETURN jsonb_build_object('success', true, 'status', 'dismissed');
  END IF;

  PERFORM set_config('thriftline.lf_write', '1', true);
  UPDATE public.looking_for_posts
  SET moderation_removed_at = COALESCE(moderation_removed_at, now())
  WHERE post_id = v_report.post_id;

  UPDATE public.looking_for_reports
  SET
    status = 'action_taken'::public.report_status_enum,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE report_id = p_report_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.looking_for_violations v
    WHERE v.post_id = v_report.post_id
  ) THEN
    SELECT count(*) + 1 INTO v_count
    FROM public.looking_for_violations v
    WHERE v.user_id = v_report.reported_user_id;

    INSERT INTO public.looking_for_violations (
      user_id, post_id, report_id, strike_number
    ) VALUES (
      v_report.reported_user_id, v_report.post_id, p_report_id, v_count
    );

    INSERT INTO public.looking_for_account_sanctions AS s (
      user_id, strike_count, updated_at
    ) VALUES (
      v_report.reported_user_id, v_count, now()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET strike_count = EXCLUDED.strike_count,
        updated_at = now();

    SELECT title INTO v_title
    FROM public.looking_for_posts
    WHERE post_id = v_report.post_id;

    IF v_count = 1 THEN
      PERFORM public.notify_user(
        v_report.reported_user_id,
        'system',
        'Looking For warning',
        'We removed your Looking For request'
          || COALESCE(' "' || left(v_title, 80) || '"', '')
          || '. This is a warning. You can still post requests.',
        jsonb_build_object('strike', 1, 'post_id', v_report.post_id)
      );
    ELSIF v_count = 2 THEN
      UPDATE public.looking_for_account_sanctions
      SET restricted_until = now() + interval '3 days',
          updated_at = now()
      WHERE user_id = v_report.reported_user_id;

      PERFORM public.notify_user(
        v_report.reported_user_id,
        'system',
        'Looking For paused',
        'We removed your Looking For request. You can''t post or repost requests for 3 days.',
        jsonb_build_object('strike', 2, 'post_id', v_report.post_id)
      );
    ELSE
      UPDATE public.looking_for_account_sanctions
      SET
        permanently_disabled_at = COALESCE(permanently_disabled_at, now()),
        restricted_until = NULL,
        disable_reason = 'Repeated confirmed Looking For violations',
        updated_at = now()
      WHERE user_id = v_report.reported_user_id;

      UPDATE public.users
      SET account_status = 'banned'::public.account_status_enum
      WHERE user_id = v_report.reported_user_id;

      PERFORM public._looking_for_disable_auth_user(v_report.reported_user_id);
      PERFORM public._looking_for_drop_auth_sessions(v_report.reported_user_id);

      PERFORM public.notify_user(
        v_report.reported_user_id,
        'system',
        'Account disabled',
        'Your account has been permanently disabled after repeated Looking For violations.',
        jsonb_build_object('strike', v_count, 'post_id', v_report.post_id)
      );
    END IF;
  END IF;

  PERFORM public.notify_user(
    v_report.reporter_id,
    'system',
    'Report reviewed',
    'We reviewed your Looking For report and took action.',
    jsonb_build_object('report_id', p_report_id, 'status', 'action_taken')
  );

  RETURN jsonb_build_object('success', true, 'status', 'action_taken');
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_my_expired_looking_for_requests()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.looking_for_posts%ROWTYPE;
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', true, 'notified', 0);
  END IF;

  PERFORM set_config('thriftline.lf_write', '1', true);
  FOR v_row IN
    SELECT *
    FROM public.looking_for_posts p
    WHERE p.user_id = v_uid
      AND p.status = 'open'::public.looking_for_status_enum
      AND p.expires_at <= now()
      AND p.expiry_notified_at IS NULL
      AND p.moderation_removed_at IS NULL
      AND p.owner_deleted_at IS NULL
    FOR UPDATE
  LOOP
    PERFORM public.notify_user(
      v_uid,
      'system',
      'Looking For request expired',
      'Your Looking For request has expired. You can repost it from Inactive Requests.',
      jsonb_build_object('post_id', v_row.post_id)
    );
    UPDATE public.looking_for_posts
    SET expiry_notified_at = now()
    WHERE post_id = v_row.post_id;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'notified', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.looking_for_server_now()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('now', now());
$$;

REVOKE ALL ON FUNCTION public.create_looking_for_request(text, text, text, numeric, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_looking_for_request(uuid, text, text, text, numeric, numeric, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_looking_for_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.repost_looking_for_request(uuid, text, text, text, numeric, numeric, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_looking_for_request(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_looking_for_report(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.notify_my_expired_looking_for_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.looking_for_server_now() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._looking_for_disable_auth_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._looking_for_drop_auth_sessions(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_looking_for_request(text, text, text, numeric, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_looking_for_request(uuid, text, text, text, numeric, numeric, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_looking_for_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repost_looking_for_request(uuid, text, text, text, numeric, numeric, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_looking_for_request(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_looking_for_report(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_my_expired_looking_for_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.looking_for_server_now() TO authenticated;
