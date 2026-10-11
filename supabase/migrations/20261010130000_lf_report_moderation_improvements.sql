-- Looking For report moderation: snapshots, decision outcomes, queue priority, sibling resolution.

-- ---------------------------------------------------------------------------
-- 1. Storage path helper (before snapshot backfill)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.looking_for_storage_path_from_url(p_url text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT NULLIF(
    btrim(
      split_part(
        coalesce(
          substring(p_url from '/object/public/looking-for/(.+)$'),
          ''
        ),
        '?',
        1
      )
    ),
    ''
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. Report snapshots and decision outcome
-- ---------------------------------------------------------------------------

ALTER TABLE public.looking_for_reports
  ADD COLUMN IF NOT EXISTS snapshot_title text,
  ADD COLUMN IF NOT EXISTS snapshot_description text,
  ADD COLUMN IF NOT EXISTS snapshot_image_path text,
  ADD COLUMN IF NOT EXISTS snapshot_captured_at timestamptz,
  ADD COLUMN IF NOT EXISTS decision_outcome text;

ALTER TABLE public.looking_for_reports
  DROP CONSTRAINT IF EXISTS looking_for_reports_decision_outcome_chk;

ALTER TABLE public.looking_for_reports
  ADD CONSTRAINT looking_for_reports_decision_outcome_chk CHECK (
    decision_outcome IS NULL
    OR decision_outcome IN (
      'violation_confirmed',
      'dismissed',
      'insufficient_evidence'
    )
  );

UPDATE public.looking_for_reports r
SET
  snapshot_title = p.title,
  snapshot_description = p.description,
  snapshot_image_path = public.looking_for_storage_path_from_url(p.reference_image_url),
  snapshot_captured_at = coalesce(r.snapshot_captured_at, r.created_at)
FROM public.looking_for_posts p
WHERE p.post_id = r.post_id
  AND r.snapshot_title IS NULL;

-- Block owners from deleting images referenced by open report snapshots.
DROP POLICY IF EXISTS looking_for_images_delete_own ON storage.objects;
CREATE POLICY looking_for_images_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'looking-for'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND NOT EXISTS (
      SELECT 1
      FROM public.looking_for_reports r
      WHERE r.snapshot_image_path = name
        AND r.status IN (
          'under_review'::public.report_status_enum,
          'needs_more_evidence'::public.report_status_enum
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Priority score for admin queue (derived; not stored)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.looking_for_report_priority_score(
  p_reason text,
  p_status text,
  p_expires_at timestamptz,
  p_report_created_at timestamptz,
  p_sibling_open_count integer,
  p_confirmed_violations integer
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_score integer := 0;
  v_reason text := lower(btrim(coalesce(p_reason, '')));
  v_hours_to_expiry numeric;
  v_hours_since_report numeric;
BEGIN
  IF p_status NOT IN ('under_review', 'needs_more_evidence') THEN
    RETURN 0;
  END IF;

  v_score := CASE v_reason
    WHEN 'explicit_content' THEN 1000
    WHEN 'scam_or_suspicious' THEN 900
    WHEN 'inappropriate_content' THEN 800
    WHEN 'spam' THEN 250
    WHEN 'unrelated_content' THEN 200
    ELSE 150
  END;

  IF p_expires_at IS NOT NULL THEN
    v_hours_to_expiry :=
      extract(epoch FROM (p_expires_at - now())) / 3600.0;
    IF v_hours_to_expiry <= 0 THEN
      v_score := v_score + 350;
    ELSIF v_hours_to_expiry <= 4 THEN
      v_score := v_score + 500;
    ELSIF v_hours_to_expiry <= 18 THEN
      v_score := v_score + 300;
    ELSIF v_hours_to_expiry <= 24 THEN
      v_score := v_score + 200;
    END IF;
  END IF;

  v_hours_since_report :=
    extract(epoch FROM (now() - p_report_created_at)) / 3600.0;
  IF v_hours_since_report >= 24 THEN
    v_score := v_score + 400;
  ELSIF v_hours_since_report >= 21 THEN
    v_score := v_score + 250;
  END IF;

  v_score := v_score + greatest(coalesce(p_sibling_open_count, 1) - 1, 0) * 15;
  v_score := v_score + least(coalesce(p_confirmed_violations, 0), 5) * 8;

  RETURN v_score;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Admin queue view (extended — new columns appended; drop required)
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS public.admin_looking_for_report_queue;

CREATE VIEW public.admin_looking_for_report_queue
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
  ) AS confirmed_violations,
  r.evidence_attempt_count,
  r.reporter_instruction,
  r.snapshot_title,
  r.snapshot_description,
  r.snapshot_image_path,
  r.snapshot_captured_at,
  r.decision_outcome,
  (
    SELECT count(*)::integer
    FROM public.looking_for_reports s
    WHERE s.post_id = r.post_id
      AND s.status IN (
        'under_review'::public.report_status_enum,
        'needs_more_evidence'::public.report_status_enum
      )
  ) AS open_reports_on_post,
  (
    SELECT coalesce(
      jsonb_object_agg(sub.reason, sub.cnt),
      '{}'::jsonb
    )
    FROM (
      SELECT s.reason, count(*)::integer AS cnt
      FROM public.looking_for_reports s
      WHERE s.post_id = r.post_id
        AND s.status IN (
          'under_review'::public.report_status_enum,
          'needs_more_evidence'::public.report_status_enum
        )
      GROUP BY s.reason
    ) sub
  ) AS open_report_reason_counts
FROM public.looking_for_reports r
JOIN public.looking_for_posts p ON p.post_id = r.post_id
JOIN public.users ru ON ru.user_id = r.reporter_id
JOIN public.users du ON du.user_id = r.reported_user_id;

GRANT SELECT ON public.admin_looking_for_report_queue TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. report_looking_for_request — snapshot + submit notification
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
  v_post public.looking_for_posts%ROWTYPE;
  v_image_path text;
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
    'explicit_content',
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

  SELECT * INTO v_post
  FROM public.looking_for_posts p
  WHERE p.post_id = p_post_id
    AND p.owner_deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN public.looking_for_fail('That request is no longer available.');
  END IF;

  v_owner := v_post.user_id;

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

  v_image_path := public.looking_for_storage_path_from_url(v_post.reference_image_url);

  BEGIN
    INSERT INTO public.looking_for_reports (
      post_id,
      reporter_id,
      reported_user_id,
      reason,
      details,
      snapshot_title,
      snapshot_description,
      snapshot_image_path,
      snapshot_captured_at
    ) VALUES (
      p_post_id,
      v_uid,
      v_owner,
      v_reason,
      v_details,
      v_post.title,
      coalesce(v_post.description, ''),
      v_image_path,
      now()
    )
    RETURNING report_id INTO v_report_id;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN public.looking_for_fail('You already reported this request.');
  END;

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Report submitted',
    'Your report has been submitted and is awaiting review.',
    jsonb_build_object('report_id', v_report_id, 'status', 'under_review')
  );

  RETURN jsonb_build_object('success', true, 'report_id', v_report_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. review_looking_for_report — outcomes, siblings, notifications
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.review_looking_for_report(
  p_report_id uuid,
  p_decision text,
  p_admin_response text DEFAULT NULL,
  p_violation_confirmed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text := lower(btrim(coalesce(p_decision, '')));
  v_response text := btrim(coalesce(p_admin_response, ''));
  v_report public.looking_for_reports%ROWTYPE;
  v_sibling public.looking_for_reports%ROWTYPE;
  v_count integer;
  v_title text;
  v_min_len integer := 8;
  v_strike_applied boolean := false;
  v_outcome text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN public.looking_for_fail('Only an admin can review this report.');
  END IF;

  IF v_decision = 'needs_more_evidence' THEN
    RETURN public.looking_for_fail(
      'Requesting more evidence is not available for Looking For reports.'
    );
  END IF;

  IF v_decision NOT IN ('resolved', 'dismissed', 'insufficient_evidence') THEN
    RETURN public.looking_for_fail('Choose a valid decision.');
  END IF;

  IF char_length(v_response) < v_min_len THEN
    RETURN public.looking_for_fail('Write a clear response for the reporter.');
  END IF;

  SELECT * INTO v_report
  FROM public.looking_for_reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.looking_for_fail('That report was not found.');
  END IF;

  IF v_report.status IN (
    'resolved'::public.report_status_enum,
    'dismissed'::public.report_status_enum
  ) THEN
    RETURN public.looking_for_fail('This report has already been reviewed.');
  END IF;

  IF v_decision = 'insufficient_evidence' THEN
    UPDATE public.looking_for_reports
    SET
      status = 'dismissed'::public.report_status_enum,
      decision_outcome = 'insufficient_evidence',
      reviewed_by = v_uid,
      resolved_at = now(),
      reporter_instruction = NULL
    WHERE report_id = p_report_id;

    PERFORM public.notify_user(
      v_report.reporter_id,
      'system',
      'Report reviewed',
      'We reviewed your report, but the available evidence was insufficient to confirm a violation.',
      jsonb_build_object(
        'report_id', p_report_id,
        'status', 'dismissed',
        'decision_outcome', 'insufficient_evidence'
      )
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'dismissed',
      'decision_outcome', 'insufficient_evidence'
    );
  END IF;

  IF v_decision = 'dismissed' THEN
    UPDATE public.looking_for_reports
    SET
      status = 'dismissed'::public.report_status_enum,
      decision_outcome = 'dismissed',
      reviewed_by = v_uid,
      resolved_at = now(),
      reporter_instruction = NULL
    WHERE report_id = p_report_id;

    PERFORM public.notify_user(
      v_report.reporter_id,
      'system',
      'Report reviewed',
      'We reviewed your report and did not find sufficient grounds for moderation.',
      jsonb_build_object(
        'report_id', p_report_id,
        'status', 'dismissed',
        'decision_outcome', 'dismissed'
      )
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'dismissed',
      'decision_outcome', 'dismissed'
    );
  END IF;

  -- resolved (confirm violation)
  IF NOT p_violation_confirmed THEN
    RETURN public.looking_for_fail(
      'Confirm that a violation occurred before resolving this report.'
    );
  END IF;

  v_outcome := 'violation_confirmed';

  PERFORM set_config('thriftline.lf_write', '1', true);
  UPDATE public.looking_for_posts
  SET moderation_removed_at = COALESCE(moderation_removed_at, now())
  WHERE post_id = v_report.post_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.looking_for_violations v WHERE v.post_id = v_report.post_id
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

    v_strike_applied := true;

    SELECT coalesce(nullif(btrim(v_report.snapshot_title), ''), p.title)
    INTO v_title
    FROM public.looking_for_posts p
    WHERE p.post_id = v_report.post_id;

    IF v_count = 1 THEN
      PERFORM public.notify_user(
        v_report.reported_user_id,
        'system',
        'Looking For request removed',
        'Your Looking For request was removed for violating ThriftLine''s community guidelines. Please review our posting policies.',
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
        'Looking For request removed',
        'Your Looking For request was removed for violating community guidelines. You can''t post or repost requests for 3 days.',
        jsonb_build_object('strike', 2, 'post_id', v_report.post_id)
      );
    ELSE
      UPDATE public.looking_for_account_sanctions
      SET
        permanently_disabled_at = coalesce(permanently_disabled_at, now()),
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
  ELSE
    PERFORM public.notify_user(
      v_report.reported_user_id,
      'system',
      'Looking For request removed',
      'Your Looking For request was removed for violating ThriftLine''s community guidelines. Please review our posting policies.',
      jsonb_build_object('post_id', v_report.post_id)
    );
  END IF;

  UPDATE public.looking_for_reports
  SET
    status = 'resolved'::public.report_status_enum,
    decision_outcome = v_outcome,
    reviewed_by = v_uid,
    resolved_at = now(),
    reporter_instruction = NULL
  WHERE report_id = p_report_id;

  FOR v_sibling IN
    SELECT *
    FROM public.looking_for_reports s
    WHERE s.post_id = v_report.post_id
      AND s.report_id <> p_report_id
      AND s.status IN (
        'under_review'::public.report_status_enum,
        'needs_more_evidence'::public.report_status_enum
      )
    FOR UPDATE
  LOOP
    UPDATE public.looking_for_reports
    SET
      status = 'resolved'::public.report_status_enum,
      decision_outcome = v_outcome,
      reviewed_by = v_uid,
      resolved_at = now(),
      reporter_instruction = NULL
    WHERE report_id = v_sibling.report_id;

    PERFORM public.notify_user(
      v_sibling.reporter_id,
      'system',
      'Report reviewed',
      'Your report has been reviewed. Thank you for helping keep ThriftLine safe.',
      jsonb_build_object(
        'report_id', v_sibling.report_id,
        'status', 'resolved',
        'decision_outcome', v_outcome
      )
    );
  END LOOP;

  PERFORM public.notify_user(
    v_report.reporter_id,
    'system',
    'Report reviewed',
    'Your report has been reviewed. Thank you for helping keep ThriftLine safe.',
    jsonb_build_object(
      'report_id', p_report_id,
      'status', 'resolved',
      'decision_outcome', v_outcome
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'status', 'resolved',
    'decision_outcome', v_outcome,
    'strike_applied', v_strike_applied
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. admin_moderation_queue — LF lifecycle filter + priority sort + metadata
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_moderation_queue(
  p_category text DEFAULT 'all',
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0,
  p_lf_lifecycle text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text := lower(trim(coalesce(p_category, 'all')));
  v_status text := lower(trim(coalesce(p_status, 'all')));
  v_lf_lifecycle text := lower(trim(coalesce(p_lf_lifecycle, 'all')));
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_limit integer := greatest(coalesce(p_limit, 10), 1);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_items jsonb;
  v_lf_priority_sort boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can view the moderation queue.'
    );
  END IF;

  IF v_category NOT IN ('all', 'community', 'order', 'looking_for') THEN
    v_category := 'all';
  END IF;

  IF v_status NOT IN (
    'all', 'under_review', 'needs_more_evidence', 'resolved', 'dismissed', 'closed'
  ) THEN
    v_status := 'all';
  END IF;

  IF v_lf_lifecycle NOT IN (
    'all', 'active_post', 'expiring_soon', 'expired_review_required', 'resolved_closed'
  ) THEN
    v_lf_lifecycle := 'all';
  END IF;

  v_lf_priority_sort := v_category = 'looking_for';

  WITH unified AS (
    SELECT
      'report'::text AS source,
      r.report_id::text AS case_id,
      r.created_at,
      r.status::text AS status_raw,
      CASE
        WHEN public.admin_is_order_linked_report(r.category::text, r.order_id)
          THEN 'order_report'
        ELSE 'community_report'
      END AS case_kind,
      coalesce(nullif(trim(r.category), ''), 'report') AS category,
      left(coalesce(nullif(trim(r.details), ''), ''), 120) AS summary,
      coalesce(
        nullif(trim(reporter.full_name), ''),
        coalesce(nullif(trim(reporter.username), ''), 'Member')
      ) AS actor_name,
      coalesce(
        nullif(trim(reported.full_name), ''),
        coalesce(nullif(trim(reported.username), ''), 'Member')
      ) AS subject_name,
      o.order_number::text AS order_number,
      r.evidence_attempt_count::int AS evidence_attempts,
      NULL::text AS lf_post_title,
      NULL::timestamptz AS lf_expires_at,
      NULL::integer AS lf_open_reports,
      NULL::integer AS lf_priority_score,
      NULL::text AS lf_decision_outcome
    FROM public.reports r
    JOIN public.users reporter ON reporter.user_id = r.reporter_id
    JOIN public.users reported ON reported.user_id = r.reported_user_id
    LEFT JOIN public.orders o ON o.order_id = r.order_id
    WHERE (
      v_category = 'all'
      OR (v_category = 'community' AND NOT public.admin_is_order_linked_report(r.category::text, r.order_id))
      OR (v_category = 'order' AND public.admin_is_order_linked_report(r.category::text, r.order_id))
    )
    UNION ALL
    SELECT
      'looking_for'::text,
      lf.report_id::text,
      lf.created_at,
      lf.status::text,
      'looking_for_report'::text,
      coalesce(nullif(trim(lf.reason), ''), 'looking_for'),
      left(coalesce(nullif(trim(lf.details), ''), ''), 120),
      coalesce(nullif(trim(lf.reporter_name), ''), lf.reporter_username, 'Member'),
      coalesce(nullif(trim(lf.reported_name), ''), lf.reported_username, 'Member'),
      NULL::text,
      lf.evidence_attempt_count::int,
      coalesce(nullif(trim(lf.snapshot_title), ''), nullif(trim(lf.post_title), ''), 'Untitled request'),
      lf.expires_at,
      lf.open_reports_on_post,
      public.looking_for_report_priority_score(
        lf.reason,
        lf.status::text,
        lf.expires_at,
        lf.created_at,
        lf.open_reports_on_post,
        lf.confirmed_violations
      ),
      lf.decision_outcome
    FROM public.admin_looking_for_report_queue lf
    WHERE v_category IN ('all', 'looking_for')
  ),
  filtered AS (
    SELECT *
    FROM unified u
    WHERE (p_from IS NULL OR u.created_at >= p_from)
      AND (p_to IS NULL OR u.created_at < p_to)
      AND (
        v_status = 'all'
        OR (v_status = 'under_review' AND u.status_raw = 'under_review')
        OR (v_status = 'needs_more_evidence' AND u.status_raw = 'needs_more_evidence')
        OR (v_status = 'resolved' AND u.status_raw = 'resolved')
        OR (v_status = 'dismissed' AND u.status_raw = 'dismissed')
        OR (v_status = 'closed' AND u.status_raw IN ('dismissed', 'resolved'))
      )
      AND (
        v_lf_lifecycle = 'all'
        OR u.source <> 'looking_for'
        OR (
          v_lf_lifecycle = 'resolved_closed'
          AND u.status_raw IN ('resolved', 'dismissed')
        )
        OR (
          v_lf_lifecycle = 'active_post'
          AND u.status_raw IN ('under_review', 'needs_more_evidence')
          AND u.lf_expires_at IS NOT NULL
          AND u.lf_expires_at > now()
        )
        OR (
          v_lf_lifecycle = 'expiring_soon'
          AND u.status_raw IN ('under_review', 'needs_more_evidence')
          AND u.lf_expires_at IS NOT NULL
          AND u.lf_expires_at > now()
          AND u.lf_expires_at <= now() + interval '24 hours'
        )
        OR (
          v_lf_lifecycle = 'expired_review_required'
          AND u.status_raw IN ('under_review', 'needs_more_evidence')
          AND u.lf_expires_at IS NOT NULL
          AND u.lf_expires_at <= now()
        )
      )
      AND (
        v_search IS NULL
        OR u.summary ILIKE ('%' || v_search || '%')
        OR u.category ILIKE ('%' || v_search || '%')
        OR u.actor_name ILIKE ('%' || v_search || '%')
        OR u.subject_name ILIKE ('%' || v_search || '%')
        OR coalesce(u.order_number, '') ILIKE ('%' || v_search || '%')
        OR u.case_id ILIKE ('%' || v_search || '%')
        OR coalesce(u.lf_post_title, '') ILIKE ('%' || v_search || '%')
      )
  )
  SELECT count(*)::int INTO v_total FROM filtered;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source', page_row.source,
        'case_id', page_row.case_id,
        'case_kind', page_row.case_kind,
        'category', page_row.category,
        'summary', page_row.summary,
        'status_raw', page_row.status_raw,
        'actor_name', page_row.actor_name,
        'subject_name', page_row.subject_name,
        'order_number', page_row.order_number,
        'created_at', page_row.created_at,
        'evidence_attempts', page_row.evidence_attempts,
        'lf_post_title', page_row.lf_post_title,
        'lf_expires_at', page_row.lf_expires_at,
        'lf_open_reports', page_row.lf_open_reports,
        'lf_priority_score', page_row.lf_priority_score,
        'lf_decision_outcome', page_row.lf_decision_outcome
      )
      ORDER BY
        CASE WHEN v_lf_priority_sort THEN page_row.lf_priority_score END DESC NULLS LAST,
        CASE WHEN v_lf_priority_sort AND page_row.status_raw IN ('under_review', 'needs_more_evidence')
          THEN page_row.created_at END ASC NULLS LAST,
        page_row.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT f.*
    FROM filtered f
    ORDER BY
      CASE WHEN v_lf_priority_sort THEN f.lf_priority_score END DESC NULLS LAST,
      CASE WHEN v_lf_priority_sort AND f.status_raw IN ('under_review', 'needs_more_evidence')
        THEN f.created_at END ASC NULLS LAST,
      f.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  ) page_row;

  RETURN jsonb_build_object(
    'success', true,
    'total', coalesce(v_total, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_moderation_queue(
  text, text, text, timestamptz, timestamptz, integer, integer
);

REVOKE ALL ON FUNCTION public.admin_moderation_queue(
  text, text, text, timestamptz, timestamptz, integer, integer, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderation_queue(
  text, text, text, timestamptz, timestamptz, integer, integer, text
) TO authenticated;
