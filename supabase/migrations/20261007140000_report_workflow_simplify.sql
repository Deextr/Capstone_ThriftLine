-- ===========================================================================
-- ThriftLine report workflow simplify (3 types, 4 statuses, 3 evidence attempts)
-- ===========================================================================
-- AUDIT APPENDIX (pre-implementation source of truth)
-- Tables: public.reports, report_evidence, delivery_disputes (internal escrow),
--   looking_for_reports, report_appeals (reported-user appeals, unchanged).
-- Overlap removed in UX: order-linked reports + dispute_id FK; delivery_disputes
--   kept internal per Phase 10. Status model: under_review, needs_more_evidence,
--   resolved, dismissed (action_taken migrated to resolved).
-- RPCs added/updated: submit_community_report, submit_order_report,
--   resubmit_report_evidence, decide_report, review_looking_for_report,
--   attach_report_evidence, abandon_open_report (restricted).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Report columns (enum value needs_more_evidence: prior migration 139900)
-- ---------------------------------------------------------------------------

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS dispute_id uuid REFERENCES public.delivery_disputes (dispute_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES public.products (product_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS evidence_attempt_count smallint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS reporter_instruction text;

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_evidence_attempt_count_chk;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_evidence_attempt_count_chk CHECK (
    evidence_attempt_count BETWEEN 1 AND 3
  );

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_reporter_instruction_len;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_reporter_instruction_len CHECK (
    reporter_instruction IS NULL OR char_length(reporter_instruction) <= 2000
  );

CREATE INDEX IF NOT EXISTS reports_dispute_id_idx ON public.reports (dispute_id);
CREATE INDEX IF NOT EXISTS reports_product_id_idx ON public.reports (product_id);

-- Backfill dispute link for order reports
UPDATE public.reports r
SET dispute_id = d.dispute_id
FROM public.delivery_disputes d
WHERE r.order_id = d.order_id
  AND r.dispute_id IS NULL;

-- Migrate legacy final status
UPDATE public.reports
SET status = 'resolved'::public.report_status_enum
WHERE status = 'action_taken'::public.report_status_enum;

UPDATE public.looking_for_reports
SET status = 'resolved'::public.report_status_enum
WHERE status = 'action_taken'::public.report_status_enum;

-- ---------------------------------------------------------------------------
-- 2. Evidence submission batches (community/order reports)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.report_evidence_submissions (
  submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.reports (report_id) ON DELETE CASCADE,
  attempt_number smallint NOT NULL,
  submitted_by uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT report_evidence_submissions_attempt_chk CHECK (attempt_number BETWEEN 1 AND 3),
  CONSTRAINT report_evidence_submissions_unique_attempt UNIQUE (report_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS report_evidence_submissions_report_idx
  ON public.report_evidence_submissions (report_id, attempt_number);

ALTER TABLE public.report_evidence
  ADD COLUMN IF NOT EXISTS submission_id uuid REFERENCES public.report_evidence_submissions (submission_id) ON DELETE SET NULL;

-- Backfill attempt 1 submissions for existing reports with evidence or all open reports
INSERT INTO public.report_evidence_submissions (report_id, attempt_number, submitted_by, submitted_at)
SELECT r.report_id, 1, r.reporter_id, coalesce(r.created_at, now())
FROM public.reports r
WHERE NOT EXISTS (
  SELECT 1 FROM public.report_evidence_submissions s WHERE s.report_id = r.report_id
)
ON CONFLICT (report_id, attempt_number) DO NOTHING;

UPDATE public.report_evidence e
SET submission_id = s.submission_id
FROM public.report_evidence_submissions s
WHERE e.report_id = s.report_id
  AND s.attempt_number = 1
  AND e.submission_id IS NULL;

ALTER TABLE public.report_evidence_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_evidence_submissions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS report_evidence_submissions_select ON public.report_evidence_submissions;
CREATE POLICY report_evidence_submissions_select ON public.report_evidence_submissions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.reports r
      WHERE r.report_id = report_evidence_submissions.report_id
        AND (r.reporter_id = auth.uid() OR public.is_admin())
    )
  );

REVOKE ALL ON TABLE public.report_evidence_submissions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.report_evidence_submissions TO authenticated;
GRANT ALL ON TABLE public.report_evidence_submissions TO postgres, service_role;

-- Active case duplicate prevention
CREATE UNIQUE INDEX IF NOT EXISTS reports_one_active_per_reporter_order_idx
  ON public.reports (reporter_id, order_id)
  WHERE order_id IS NOT NULL
    AND status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    );

CREATE UNIQUE INDEX IF NOT EXISTS reports_one_active_community_product_idx
  ON public.reports (reporter_id, product_id, category)
  WHERE product_id IS NOT NULL
    AND order_id IS NULL
    AND status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    );

-- ---------------------------------------------------------------------------
-- 3. Looking For: reasons, columns, evidence
-- ---------------------------------------------------------------------------

ALTER TABLE public.looking_for_reports
  ADD COLUMN IF NOT EXISTS evidence_attempt_count smallint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS reporter_instruction text;

ALTER TABLE public.looking_for_reports
  DROP CONSTRAINT IF EXISTS looking_for_reports_evidence_attempt_count_chk;

ALTER TABLE public.looking_for_reports
  ADD CONSTRAINT looking_for_reports_evidence_attempt_count_chk CHECK (
    evidence_attempt_count BETWEEN 1 AND 3
  );

ALTER TABLE public.looking_for_reports DROP CONSTRAINT IF EXISTS looking_for_reports_reason_check;
ALTER TABLE public.looking_for_reports ADD CONSTRAINT looking_for_reports_reason_check CHECK (
  reason IN (
    'spam',
    'unrelated_content',
    'inappropriate_content',
    'explicit_content',
    'scam_or_suspicious',
    'other'
  )
);

CREATE TABLE IF NOT EXISTS public.looking_for_evidence_submissions (
  submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.looking_for_reports (report_id) ON DELETE CASCADE,
  attempt_number smallint NOT NULL,
  submitted_by uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lf_evidence_submissions_attempt_chk CHECK (attempt_number BETWEEN 1 AND 3),
  CONSTRAINT lf_evidence_submissions_unique_attempt UNIQUE (report_id, attempt_number)
);

CREATE TABLE IF NOT EXISTS public.looking_for_report_evidence (
  evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.looking_for_reports (report_id) ON DELETE CASCADE,
  submission_id uuid REFERENCES public.looking_for_evidence_submissions (submission_id) ON DELETE SET NULL,
  file_path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT looking_for_report_evidence_path_unique UNIQUE (file_path)
);

CREATE INDEX IF NOT EXISTS looking_for_report_evidence_report_idx
  ON public.looking_for_report_evidence (report_id);

ALTER TABLE public.looking_for_evidence_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_evidence_submissions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_report_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_report_evidence FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lf_evidence_submissions_select ON public.looking_for_evidence_submissions;
CREATE POLICY lf_evidence_submissions_select ON public.looking_for_evidence_submissions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.looking_for_reports r
      WHERE r.report_id = looking_for_evidence_submissions.report_id
        AND (r.reporter_id = auth.uid() OR public.is_admin())
    )
  );

DROP POLICY IF EXISTS lf_report_evidence_select ON public.looking_for_report_evidence;
CREATE POLICY lf_report_evidence_select ON public.looking_for_report_evidence
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.looking_for_reports r
      WHERE r.report_id = looking_for_report_evidence.report_id
        AND (r.reporter_id = auth.uid() OR public.is_admin())
    )
  );

REVOKE ALL ON TABLE public.looking_for_evidence_submissions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.looking_for_report_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.looking_for_evidence_submissions TO authenticated;
GRANT SELECT ON TABLE public.looking_for_report_evidence TO authenticated;
GRANT ALL ON TABLE public.looking_for_evidence_submissions TO postgres, service_role;
GRANT ALL ON TABLE public.looking_for_report_evidence TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 4. Category constraints (community vs order slugs)
-- ---------------------------------------------------------------------------

ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_category_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_category_check CHECK (
  category IN (
    'scam_or_fraud',
    'counterfeit_item',
    'fake_item',
    'harassment',
    'abusive_behavior',
    'suspicious_activity',
    'fake_identity',
    'other',
    'fake_product',
    'failure_to_ship',
    'item_not_as_described',
    'inappropriate_messages',
    'seller_not_processing_order',
    'counterfeit_received',
    'undisclosed_damage',
    'buyer_delivery_pin_issue'
  )
);

-- Map legacy categories on existing rows
UPDATE public.reports SET category = 'abusive_behavior' WHERE category = 'inappropriate_messages';
UPDATE public.reports SET category = 'fake_item' WHERE category = 'fake_product' AND order_id IS NULL;
UPDATE public.reports SET category = 'counterfeit_received' WHERE category = 'counterfeit_item' AND order_id IS NOT NULL;
UPDATE public.reports SET category = 'suspicious_activity' WHERE category = 'failure_to_ship' AND order_id IS NULL;

-- ---------------------------------------------------------------------------
-- 5. Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._report_is_order_linked(
  p_category text,
  p_order_id uuid
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_order_id IS NOT NULL
    OR p_category = ANY (
      ARRAY[
        'seller_not_processing_order',
        'counterfeit_received',
        'item_not_as_described',
        'undisclosed_damage',
        'buyer_delivery_pin_issue',
        'fake_product',
        'counterfeit_item',
        'failure_to_ship'
      ]::text[]
    );
$$;

CREATE OR REPLACE FUNCTION public._ensure_report_submission(
  p_report_id uuid,
  p_attempt integer,
  p_submitted_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_attempt smallint;
BEGIN
  IF p_attempt IS NULL OR p_attempt NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'Invalid evidence attempt %', p_attempt;
  END IF;
  v_attempt := p_attempt::smallint;

  INSERT INTO public.report_evidence_submissions (
    report_id, attempt_number, submitted_by
  ) VALUES (
    p_report_id, v_attempt, p_submitted_by
  )
  ON CONFLICT (report_id, attempt_number) DO UPDATE
    SET submitted_at = public.report_evidence_submissions.submitted_at
  RETURNING submission_id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. submit_community_report
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_community_report(
  p_reported_user_id uuid,
  p_category text,
  p_details text,
  p_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text;
  v_details text;
  v_report_id uuid;
  v_submission_id uuid;
  v_recent integer;
  v_too_fast constant text :=
    'You''re submitting reports too quickly. Please wait a moment and try again.';
  v_community_categories constant text[] := ARRAY[
    'scam_or_fraud',
    'counterfeit_item',
    'fake_item',
    'harassment',
    'abusive_behavior',
    'suspicious_activity',
    'fake_identity',
    'other'
  ];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_reported_user_id IS NULL OR p_reported_user_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You cannot report yourself.');
  END IF;

  v_category := lower(btrim(coalesce(p_category, '')));
  IF NOT (v_category = ANY (v_community_categories)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
  END IF;

  IF public._report_is_order_linked(v_category, NULL) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'For order-related issues, use an Order Report from your order.'
    );
  END IF;

  v_details := btrim(coalesce(p_details, ''));
  IF char_length(v_details) < 10 OR char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please add between 10 and 1,000 characters.');
  END IF;

  IF p_product_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.products p WHERE p.product_id = p_product_id
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'That listing was not found.');
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reports r
    WHERE r.reporter_id = v_uid AND r.created_at >= now() - interval '30 seconds'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', v_too_fast);
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.reports r
  WHERE r.reporter_id = v_uid AND r.created_at >= now() - interval '24 hours';
  IF v_recent >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You can submit up to 5 reports per day. Please try again tomorrow.'
    );
  END IF;

  INSERT INTO public.reports (
    reporter_id, reported_user_id, product_id, category, details, status, evidence_attempt_count
  ) VALUES (
    v_uid, p_reported_user_id, p_product_id, v_category, v_details,
    'under_review'::public.report_status_enum, 1
  )
  RETURNING report_id INTO v_report_id;

  v_submission_id := public._ensure_report_submission(v_report_id, 1, v_uid);

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Report submitted',
    'Your report has been submitted and is under review.',
    jsonb_build_object('report_id', v_report_id, 'status', 'under_review')
  );

  RETURN jsonb_build_object(
    'success', true,
    'report_id', v_report_id,
    'submission_id', v_submission_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have an active report for this listing.'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. submit_order_report
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_order_report(
  p_order_id uuid,
  p_category text,
  p_details text,
  p_delivery_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text;
  v_details text;
  v_order public.orders%ROWTYPE;
  v_report_id uuid;
  v_submission_id uuid;
  v_reported uuid;
  v_buyer_categories constant text[] := ARRAY[
    'seller_not_processing_order',
    'counterfeit_received',
    'item_not_as_described',
    'undisclosed_damage',
    'counterfeit_item',
    'fake_product',
    'failure_to_ship',
    'other'
  ];
  v_seller_categories constant text[] := ARRAY[
    'buyer_delivery_pin_issue',
    'other'
  ];
BEGIN
  IF v_uid IS NULL OR p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  v_category := lower(btrim(coalesce(p_category, '')));
  v_details := btrim(coalesce(p_details, ''));

  IF v_order.buyer_id = v_uid THEN
    IF NOT (v_category = ANY (v_buyer_categories)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
    END IF;
    v_reported := v_order.seller_id;
  ELSIF v_order.seller_id = v_uid THEN
    IF NOT (v_category = ANY (v_seller_categories)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
    END IF;
    v_reported := v_order.buyer_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'You are not part of this order.');
  END IF;

  IF v_reported IS NULL OR v_reported = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
  END IF;

  IF char_length(v_details) < 10 OR char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please add between 10 and 1,000 characters.');
  END IF;

  IF v_order.order_status IN (
    'pending'::public.order_status_enum,
    'cancelled'::public.order_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reports r
    WHERE r.reporter_id = v_uid
      AND r.order_id = p_order_id
      AND r.status IN (
        'under_review'::public.report_status_enum,
        'needs_more_evidence'::public.report_status_enum
      )
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have an active report for this order.'
    );
  END IF;

  INSERT INTO public.reports (
    reporter_id, reported_user_id, order_id, category, details, status, evidence_attempt_count
  ) VALUES (
    v_uid, v_reported, p_order_id, v_category, v_details,
    'under_review'::public.report_status_enum, 1
  )
  RETURNING report_id INTO v_report_id;

  v_submission_id := public._ensure_report_submission(v_report_id, 1, v_uid);

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Report submitted',
    'Your report has been submitted and is under review.',
    jsonb_build_object('report_id', v_report_id, 'status', 'under_review')
  );

  RETURN jsonb_build_object(
    'success', true,
    'report_id', v_report_id,
    'submission_id', v_submission_id,
    'delivery_reason', p_delivery_reason
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have an active report for this order.'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. attach_report_evidence (per submission, max 3 photos per attempt)
-- ---------------------------------------------------------------------------

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
    IF v_report.evidence_attempt_count >= 3 THEN
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

-- ---------------------------------------------------------------------------
-- 9. resubmit_report_evidence
-- ---------------------------------------------------------------------------

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

  IF v_report.evidence_attempt_count >= 3 THEN
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
    'submission_id', v_submission_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. decide_report (admin)
-- ---------------------------------------------------------------------------

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
    IF v_report.evidence_attempt_count >= 3 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Maximum evidence attempts reached. Resolve or dismiss this report.'
      );
    END IF;
    IF v_report.status NOT IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    ) THEN
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
      'attempt_number', v_report.evidence_attempt_count
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

-- ---------------------------------------------------------------------------
-- 11. abandon_open_report — disabled (anti-bypass)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.abandon_open_report(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Reports can no longer be deleted after submission.'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. submit_report — backward-compatible wrapper (community)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_report(
  p_reported_user_id uuid,
  p_category text,
  p_details text,
  p_order_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_order_id IS NOT NULL THEN
    RETURN public.submit_order_report(p_order_id, p_category, p_details, NULL);
  END IF;
  RETURN public.submit_community_report(p_reported_user_id, p_category, p_details, NULL);
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Notifications trigger — include needs_more_evidence transitions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notify_report_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status IN (
       'resolved'::public.report_status_enum,
       'dismissed'::public.report_status_enum
     )
     AND OLD.status IN (
       'under_review'::public.report_status_enum,
       'needs_more_evidence'::public.report_status_enum
     )
  THEN
    PERFORM public.notify_user(
      NEW.reporter_id,
      'report_decision',
      'Report update',
      'We reviewed your report. Open My Reports to see the decision.',
      jsonb_build_object(
        'report_id', NEW.report_id,
        'status', NEW.status::text
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. admin_is_order_linked_report — align with helper
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_is_order_linked_report(
  p_category text,
  p_order_id uuid
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public._report_is_order_linked(p_category, p_order_id);
$$;

REVOKE ALL ON FUNCTION public.submit_community_report(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_community_report(uuid, text, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_order_report(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_order_report(uuid, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.resubmit_report_evidence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resubmit_report_evidence(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.decide_report(uuid, text, text);

REVOKE ALL ON FUNCTION public.decide_report(uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_report(uuid, text, text, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 15. review_looking_for_report (admin — 4-status model)
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
  v_count integer;
  v_title text;
  v_min_len integer := 8;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN public.looking_for_fail('Only an admin can review this report.');
  END IF;

  IF v_decision NOT IN ('needs_more_evidence', 'resolved', 'dismissed') THEN
    RETURN public.looking_for_fail('Choose a valid decision.');
  END IF;

  IF v_decision = 'needs_more_evidence' THEN
    v_min_len := 20;
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

  IF v_decision = 'needs_more_evidence' THEN
    IF v_report.evidence_attempt_count >= 3 THEN
      RETURN public.looking_for_fail(
        'Maximum evidence attempts reached. Resolve or dismiss this report.'
      );
    END IF;

    UPDATE public.looking_for_reports
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

    RETURN jsonb_build_object('success', true, 'status', 'needs_more_evidence');
  END IF;

  IF v_decision = 'dismissed' THEN
    UPDATE public.looking_for_reports
    SET
      status = 'dismissed'::public.report_status_enum,
      reviewed_by = v_uid,
      resolved_at = now(),
      reporter_instruction = NULL
    WHERE report_id = p_report_id;

    PERFORM public.notify_user(
      v_report.reporter_id,
      'system',
      'Report dismissed',
      'Your report has been dismissed.',
      jsonb_build_object('report_id', p_report_id, 'status', 'dismissed')
    );

    RETURN jsonb_build_object('success', true, 'status', 'dismissed');
  END IF;

  -- resolved
  UPDATE public.looking_for_reports
  SET
    status = 'resolved'::public.report_status_enum,
    reviewed_by = v_uid,
    resolved_at = now(),
    reporter_instruction = NULL
  WHERE report_id = p_report_id;

  IF p_violation_confirmed THEN
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

      SELECT title INTO v_title
      FROM public.looking_for_posts
      WHERE post_id = v_report.post_id;

      IF v_count = 1 THEN
        PERFORM public.notify_user(
          v_report.reported_user_id,
          'system',
          'Looking For warning',
          'We removed your Looking For request'
            || coalesce(' "' || left(v_title, 80) || '"', '')
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
    END IF;
  END IF;

  PERFORM public.notify_user(
    v_report.reporter_id,
    'system',
    'Report resolved',
    'Your report has been resolved.',
    jsonb_build_object('report_id', p_report_id, 'status', 'resolved')
  );

  RETURN jsonb_build_object('success', true, 'status', 'resolved');
END;
$$;

DROP FUNCTION IF EXISTS public.review_looking_for_report(uuid, text);

REVOKE ALL ON FUNCTION public.review_looking_for_report(uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_looking_for_report(uuid, text, text, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 16. admin_moderation_queue — needs_more_evidence filter + attempt counts
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_moderation_queue(
  p_category text DEFAULT 'all',
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0
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
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_limit integer := greatest(coalesce(p_limit, 10), 1);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_items jsonb;
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
      r.evidence_attempt_count::int AS evidence_attempts
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
      lf.evidence_attempt_count::int
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
        v_search IS NULL
        OR u.summary ILIKE ('%' || v_search || '%')
        OR u.category ILIKE ('%' || v_search || '%')
        OR u.actor_name ILIKE ('%' || v_search || '%')
        OR u.subject_name ILIKE ('%' || v_search || '%')
        OR coalesce(u.order_number, '') ILIKE ('%' || v_search || '%')
        OR u.case_id ILIKE ('%' || v_search || '%')
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
        'evidence_attempts', page_row.evidence_attempts
      )
      ORDER BY page_row.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT f.*
    FROM filtered f
    ORDER BY f.created_at DESC
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

-- New columns must be appended; CREATE OR REPLACE cannot reorder view columns.
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
  ) AS confirmed_violations,
  r.evidence_attempt_count,
  r.reporter_instruction
FROM public.looking_for_reports r
JOIN public.looking_for_posts p ON p.post_id = r.post_id
JOIN public.users ru ON ru.user_id = r.reporter_id
JOIN public.users du ON du.user_id = r.reported_user_id;
