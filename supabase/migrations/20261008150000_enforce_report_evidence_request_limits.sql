-- Align admin evidence-request limits with reporter submission rounds (max 3).
-- Must stay in sync with kReportMaxEvidenceAttempts in report_reasons.dart.

CREATE OR REPLACE FUNCTION public.report_max_evidence_attempts()
RETURNS smallint
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT 3::smallint;
$$;

CREATE OR REPLACE FUNCTION public.decide_report(
  p_report_id uuid,
  p_decision text,
  p_admin_response text,
  p_violation_confirmed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_response text;
  v_report public.reports%ROWTYPE;
  v_min_len integer := 8;
  v_max smallint := public.report_max_evidence_attempts();
  v_limit_msg constant text :=
    'Evidence request limit reached. No additional evidence requests can be sent for this dispute.';
  v_pending_msg constant text :=
    'Waiting for the reporter to submit the requested evidence.';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can review reports.');
  END IF;

  v_decision := lower(btrim(coalesce(p_decision, '')));
  IF v_decision NOT IN ('needs_more_evidence', 'resolved', 'dismissed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a valid decision.');
  END IF;

  v_response := btrim(coalesce(p_admin_response, ''));
  IF v_decision = 'needs_more_evidence' THEN
    v_min_len := 20;
  END IF;

  IF char_length(v_response) < v_min_len THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Write a clear response for the reporter.'
    );
  END IF;

  IF char_length(v_response) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the response under 2,000 characters.'
    );
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status IN (
    'resolved'::public.report_status_enum,
    'dismissed'::public.report_status_enum
  ) THEN
    IF v_report.status::text = v_decision THEN
      RETURN jsonb_build_object(
        'success', true,
        'already_decided', true,
        'report_id', v_report.report_id,
        'status', v_report.status::text
      );
    END IF;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This report has already been reviewed.'
    );
  END IF;

  IF v_decision = 'needs_more_evidence' THEN
    IF v_report.evidence_attempt_count >= v_max THEN
      RETURN jsonb_build_object('success', false, 'error', v_limit_msg);
    END IF;

    IF v_report.status = 'needs_more_evidence'::public.report_status_enum THEN
      RETURN jsonb_build_object('success', false, 'error', v_pending_msg);
    END IF;

    IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
      RETURN jsonb_build_object('success', false, 'error', 'This report cannot accept that decision.');
    END IF;

    UPDATE public.reports
    SET
      status = 'needs_more_evidence'::public.report_status_enum,
      reporter_instruction = v_response,
      reviewed_by = v_uid
    WHERE report_id = p_report_id;

    PERFORM public.notify_user(
      v_report.reporter_id,
      'system',
      'More evidence required',
      'Additional evidence is needed for your report.',
      jsonb_build_object('report_id', p_report_id, 'status', 'needs_more_evidence')
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'needs_more_evidence',
      'attempt_number', v_report.evidence_attempt_count,
      'evidence_attempt_count', v_report.evidence_attempt_count
    );
  END IF;

  UPDATE public.reports
  SET
    status = v_decision::public.report_status_enum,
    admin_response = v_response,
    reporter_instruction = NULL,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE report_id = p_report_id
    AND status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report has already been reviewed.');
  END IF;

  IF v_decision = 'dismissed' AND v_report.order_id IS NOT NULL THEN
    PERFORM public._admin_finalize_dismissed_order_report(
      v_report.order_id,
      v_uid,
      v_response
    );
  END IF;

  PERFORM public.notify_user(
    v_report.reporter_id,
    'report_decision',
    CASE WHEN v_decision = 'resolved' THEN 'Report resolved' ELSE 'Report dismissed' END,
    CASE WHEN v_decision = 'resolved'
      THEN 'Your report has been resolved.'
      ELSE 'Your report has been dismissed.'
    END,
    jsonb_build_object('report_id', p_report_id, 'status', v_decision)
  );

  RETURN jsonb_build_object(
    'success', true,
    'status', v_decision,
    'report_id', p_report_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.attach_report_evidence(
  p_report_id uuid,
  p_file_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
  v_prefix text;
  v_path text;
  v_count integer;
  v_id uuid;
  v_submission_id uuid;
  v_attempt smallint;
  v_max smallint := public.report_max_evidence_attempts();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_path := NULLIF(btrim(coalesce(p_file_path, '')), '');
  IF v_path IS NULL OR v_path LIKE '%..%' OR v_path LIKE '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.reporter_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status NOT IN (
    'under_review'::public.report_status_enum,
    'needs_more_evidence'::public.report_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report can no longer accept photos.');
  END IF;

  IF v_report.status = 'needs_more_evidence'::public.report_status_enum THEN
    IF v_report.evidence_attempt_count >= v_max THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'You have used all evidence submission attempts for this report.'
      );
    END IF;
    v_attempt := v_report.evidence_attempt_count + 1;
  ELSE
    v_attempt := v_report.evidence_attempt_count;
  END IF;

  v_submission_id := public._ensure_report_submission(p_report_id, v_attempt, v_uid);

  v_prefix := v_uid::text || '/' || p_report_id::text || '/';
  IF left(v_path, char_length(v_prefix)) IS DISTINCT FROM v_prefix THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  IF lower(v_path) !~ '\.(jpe?g|png|webp)$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please upload a JPG, PNG, or WebP photo.');
  END IF;

  SELECT count(*) INTO v_count
  FROM public.report_evidence e
  WHERE e.submission_id = v_submission_id;

  IF v_count >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can attach up to 3 photos for this submission.');
  END IF;

  INSERT INTO public.report_evidence (report_id, file_path, submission_id)
  VALUES (p_report_id, v_path, v_submission_id)
  RETURNING report_evidence_id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_evidence_id', v_id,
    'attempt_number', v_attempt
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo is already attached.');
END;
$$;

CREATE OR REPLACE FUNCTION public.resubmit_report_evidence(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
  v_next smallint;
  v_submission_id uuid;
  v_photo_count integer;
  v_max smallint := public.report_max_evidence_attempts();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.reporter_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status IS DISTINCT FROM 'needs_more_evidence'::public.report_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report is not waiting for more evidence.');
  END IF;

  IF v_report.evidence_attempt_count >= v_max THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You have used all evidence submission attempts for this report.'
    );
  END IF;

  SELECT count(*) INTO v_photo_count
  FROM public.report_evidence e
  JOIN public.report_evidence_submissions s ON s.submission_id = e.submission_id
  WHERE s.report_id = p_report_id
    AND s.attempt_number = v_report.evidence_attempt_count + 1;

  IF v_photo_count < 1 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Please attach at least one photo before submitting.'
    );
  END IF;

  v_next := v_report.evidence_attempt_count + 1;

  UPDATE public.reports
  SET
    status = 'under_review'::public.report_status_enum,
    evidence_attempt_count = v_next,
    reporter_instruction = NULL
  WHERE report_id = p_report_id;

  v_submission_id := public._ensure_report_submission(p_report_id, v_next, v_uid);

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Evidence received',
    'Your additional evidence has been submitted.',
    jsonb_build_object('report_id', p_report_id, 'attempt', v_next)
  );

  RETURN jsonb_build_object(
    'success', true,
    'report_id', p_report_id,
    'attempt_number', v_next,
    'submission_id', v_submission_id,
    'evidence_attempt_count', v_next
  );
END;
$$;
