-- Report details: 1,000 char cap (client + RPC + CHECK) and submission abuse guards.

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_details_len;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_details_len CHECK (
    char_length(details) BETWEEN 10 AND 1000
  );

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
DECLARE
  v_uid uuid := auth.uid();
  v_category text;
  v_details text;
  v_order public.orders%ROWTYPE;
  v_report_id uuid;
  v_recent integer;
  v_too_fast constant text :=
    'You''re submitting reports too quickly. Please wait a moment and try again.';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_reported_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose who you are reporting.');
  END IF;

  IF p_reported_user_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You cannot report yourself.');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.users u WHERE u.user_id = p_reported_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'That user was not found.');
  END IF;

  v_category := lower(NULLIF(btrim(COALESCE(p_category, '')), ''));
  IF v_category NOT IN (
    'scam_or_fraud',
    'fake_product',
    'counterfeit_item',
    'harassment',
    'inappropriate_messages',
    'failure_to_ship',
    'item_not_as_described',
    'fake_identity',
    'other'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please choose a valid reason.');
  END IF;

  IF char_length(COALESCE(p_details, '')) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep your report under 1,000 characters.'
    );
  END IF;

  v_details := btrim(COALESCE(p_details, ''));
  IF char_length(v_details) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please add a bit more detail.');
  END IF;
  IF char_length(v_details) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep your report under 1,000 characters.'
    );
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT * INTO v_order
    FROM public.orders
    WHERE order_id = p_order_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
    END IF;

    IF NOT (
      (v_order.buyer_id = v_uid AND v_order.seller_id = p_reported_user_id)
      OR (v_order.seller_id = v_uid AND v_order.buyer_id = p_reported_user_id)
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'That order cannot be linked to this report.');
    END IF;

    IF v_order.order_status IN (
      'pending'::public.order_status_enum,
      'cancelled'::public.order_status_enum
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'That order cannot be linked to this report.'
      );
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reports r
    WHERE r.reporter_id = v_uid
      AND r.created_at >= now() - interval '30 seconds'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', v_too_fast);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reports r
    WHERE r.reporter_id = v_uid
      AND r.reported_user_id = p_reported_user_id
      AND r.category = v_category
      AND r.details = v_details
      AND r.created_at >= now() - interval '15 minutes'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', v_too_fast);
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.reports r
  WHERE r.reporter_id = v_uid
    AND r.created_at >= now() - interval '24 hours';

  IF v_recent >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You can submit up to 5 reports per day. Please try again tomorrow.'
    );
  END IF;

  INSERT INTO public.reports (
    reporter_id,
    reported_user_id,
    order_id,
    category,
    details,
    status
  )
  VALUES (
    v_uid,
    p_reported_user_id,
    p_order_id,
    v_category,
    v_details,
    'under_review'::public.report_status_enum
  )
  RETURNING report_id INTO v_report_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_id', v_report_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_report(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_report(uuid, text, text, uuid) TO authenticated;
