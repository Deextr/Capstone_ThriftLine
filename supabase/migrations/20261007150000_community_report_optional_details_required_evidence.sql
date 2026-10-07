-- Community seller reports: optional details (required for "other"), required photo evidence.

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_details_len;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_details_len CHECK (
    char_length(details) BETWEEN 0 AND 1000
  );

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
    'misleading_listing',
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
    'misleading_listing',
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
    RETURN jsonb_build_object('success', false, 'error', 'Select a reason for your report.');
  END IF;

  IF public._report_is_order_linked(v_category, NULL) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'For order-related issues, use an Order Report from your order.'
    );
  END IF;

  v_details := btrim(coalesce(p_details, ''));

  IF v_category = 'other' THEN
    IF char_length(v_details) < 10 OR char_length(v_details) > 1000 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Please describe the issue (10–1,000 characters).'
      );
    END IF;
  ELSIF char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep your report under 1,000 characters.'
    );
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

-- Finalize after client uploads evidence; removes orphan reports with zero photos.
CREATE OR REPLACE FUNCTION public.confirm_community_report_submission(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
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

  IF v_report.order_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid report type.');
  END IF;

  SELECT count(*) INTO v_photo_count
  FROM public.report_evidence e
  WHERE e.report_id = p_report_id;

  IF v_photo_count < 1 THEN
    DELETE FROM public.reports WHERE report_id = p_report_id AND reporter_id = v_uid;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Add at least one photo as evidence.'
    );
  END IF;

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Report submitted',
    'Your report has been submitted and is under review.',
    jsonb_build_object('report_id', p_report_id, 'status', 'under_review')
  );

  RETURN jsonb_build_object('success', true, 'report_id', p_report_id);
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_community_report_submission(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_community_report_submission(uuid) TO authenticated;
