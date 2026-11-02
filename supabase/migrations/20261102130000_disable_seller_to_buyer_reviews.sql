-- Reviews are buyer → seller only. Block new seller → buyer ratings and keep
-- seller shop scores based on buyer_to_seller reviews only.

CREATE OR REPLACE FUNCTION public.refresh_user_rating(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
  v_avg numeric;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('thriftline.maintain_ratings', '1', true);

  SELECT count(*), round(avg(rating)::numeric, 2)
    INTO v_count, v_avg
  FROM public.reviews
  WHERE reviewed_user_id = p_user_id
    AND review_type = 'buyer_to_seller'::public.review_type_enum;

  UPDATE public.users
  SET rating_count   = COALESCE(v_count, 0),
      rating_average = CASE WHEN COALESCE(v_count, 0) = 0 THEN 0 ELSE v_avg END,
      updated_at     = now()
  WHERE user_id = p_user_id;

  PERFORM set_config('thriftline.maintain_ratings', '0', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_review(
  p_order_id uuid,
  p_rating smallint,
  p_review_text text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_reviewed uuid;
  v_type public.review_type_enum;
  v_text text;
  v_review_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a rating from 1 to 5 stars.');
  END IF;

  v_text := NULLIF(btrim(COALESCE(p_review_text, '')), '');
  IF v_text IS NOT NULL AND char_length(v_text) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep your comment under 1,000 characters.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'completed'::public.order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can review only after this order is completed.');
  END IF;

  IF v_uid = v_order.buyer_id THEN
    v_reviewed := v_order.seller_id;
    v_type := 'buyer_to_seller'::public.review_type_enum;
  ELSIF v_uid = v_order.seller_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only buyers can review sellers on ThriftLine.'
    );
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'You can only review the other person on this order.');
  END IF;

  IF v_reviewed IS NULL OR v_reviewed = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You cannot review yourself.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reviews r
    WHERE r.order_id = p_order_id
      AND r.reviewer_id = v_uid
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already reviewed this order.');
  END IF;

  INSERT INTO public.reviews (
    order_id,
    reviewer_id,
    reviewed_user_id,
    review_type,
    rating,
    review_text
  )
  VALUES (
    p_order_id,
    v_uid,
    v_reviewed,
    v_type,
    p_rating,
    v_text
  )
  RETURNING review_id INTO v_review_id;

  PERFORM public.notify_user(
    v_reviewed,
    'review',
    'New Review',
    'You received a new review from a completed transaction.',
    jsonb_build_object(
      'review_id', v_review_id,
      'order_id', p_order_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'review_id', v_review_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already reviewed this order.');
END;
$$;

CREATE OR REPLACE FUNCTION public.update_review(
  p_review_id uuid,
  p_rating smallint,
  p_review_text text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_review public.reviews%ROWTYPE;
  v_text text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a rating from 1 to 5 stars.');
  END IF;

  v_text := NULLIF(btrim(COALESCE(p_review_text, '')), '');
  IF v_text IS NOT NULL AND char_length(v_text) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep your comment under 1,000 characters.');
  END IF;

  SELECT * INTO v_review
  FROM public.reviews
  WHERE review_id = p_review_id
  FOR UPDATE;

  IF NOT FOUND OR v_review.reviewer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Review not found.');
  END IF;

  IF v_review.review_type IS DISTINCT FROM 'buyer_to_seller'::public.review_type_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This review can no longer be edited.'
    );
  END IF;

  IF v_review.created_at <= (now() - interval '24 hours') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Reviews can be edited for 24 hours after you submit them.'
    );
  END IF;

  UPDATE public.reviews
  SET rating = p_rating,
      review_text = v_text
  WHERE review_id = p_review_id;

  RETURN jsonb_build_object('success', true, 'review_id', p_review_id);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_review(uuid, smallint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_review(uuid, smallint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_review(uuid, smallint, text) TO authenticated;

-- Recompute public rating columns (buyer_to_seller only).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT DISTINCT reviewed_user_id FROM public.reviews LOOP
    PERFORM public.refresh_user_rating(r.reviewed_user_id);
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'recalculate_seller_trust') THEN
      PERFORM public.recalculate_seller_trust(r.reviewed_user_id);
    END IF;
  END LOOP;
END;
$$;
