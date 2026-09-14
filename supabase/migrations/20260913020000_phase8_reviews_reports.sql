-- Phase 8 — Reviews and community reports.
--
-- Makes post-transaction reviews and community safety reports persistent and
-- server-enforced. Does not add trust-score math, payouts, escrow release, or
-- an admin Flutter dashboard. Admins moderate reports in Supabase Studio.
--
-- Hosted projects may already have a foundation `reviews` table plus a weak
-- `handle_review_change` trigger. This migration reuses that table, adds the
-- missing invariants, and closes the client INSERT/UPDATE hole.
--
-- Idempotent. Safe to re-run. Do not edit earlier migrations.

-- ===========================================================================
-- 1. users.rating_* may be maintained by a trusted trigger
-- ===========================================================================
-- Ordinary clients still cannot write rating_average / rating_count.
-- The review aggregate trigger sets thriftline.maintain_ratings = 1 for the
-- current transaction so those two columns can be refreshed.

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR auth.role() = 'service_role'
     OR public.is_admin()
  THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.role              := OLD.role;
  NEW.trust_score       := OLD.trust_score;
  NEW.account_status    := OLD.account_status;
  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Keeps privileged users columns inert for ordinary clients. rating_average and rating_count may change only when thriftline.maintain_ratings=1.';

-- ===========================================================================
-- 2. Enums
-- ===========================================================================

DO $$
BEGIN
  CREATE TYPE public.review_type_enum AS ENUM ('buyer_to_seller', 'seller_to_buyer');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  CREATE TYPE public.report_status_enum AS ENUM (
    'under_review',
    'action_taken',
    'resolved',
    'dismissed'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

-- ===========================================================================
-- 3. Reviews
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.reviews (
  review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  reviewed_user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  review_type public.review_type_enum NOT NULL,
  rating smallint NOT NULL,
  review_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reviews_no_self CHECK (reviewer_id <> reviewed_user_id),
  CONSTRAINT reviews_rating_range CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT reviews_text_len CHECK (
    review_text IS NULL OR char_length(review_text) <= 1000
  ),
  CONSTRAINT reviews_one_per_reviewer_per_order UNIQUE (order_id, reviewer_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reviews_no_self'
      AND conrelid = 'public.reviews'::regclass
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_no_self CHECK (reviewer_id <> reviewed_user_id);
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reviews_rating_range'
      AND conrelid = 'public.reviews'::regclass
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_rating_range CHECK (rating BETWEEN 1 AND 5);
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reviews_text_len'
      AND conrelid = 'public.reviews'::regclass
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_text_len CHECK (
        review_text IS NULL OR char_length(review_text) <= 1000
      );
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reviews_one_per_reviewer_per_order'
      AND conrelid = 'public.reviews'::regclass
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_one_per_reviewer_per_order
      UNIQUE (order_id, reviewer_id);
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE INDEX IF NOT EXISTS reviews_reviewed_user_created_idx
  ON public.reviews (reviewed_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS reviews_order_idx
  ON public.reviews (order_id);

CREATE INDEX IF NOT EXISTS reviews_reviewer_order_idx
  ON public.reviews (reviewer_id, order_id);

DROP TRIGGER IF EXISTS trg_reviews_updated_at ON public.reviews;
CREATE TRIGGER trg_reviews_updated_at
BEFORE UPDATE ON public.reviews
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

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
  WHERE reviewed_user_id = p_user_id;

  UPDATE public.users
  SET rating_count   = v_count,
      rating_average = CASE WHEN v_count = 0 THEN 0 ELSE v_avg END,
      updated_at     = now()
  WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_user_rating(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_user_rating(uuid) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.handle_review_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_user_rating(OLD.reviewed_user_id);
    RETURN OLD;
  END IF;

  PERFORM public.refresh_user_rating(NEW.reviewed_user_id);
  IF TG_OP = 'UPDATE'
     AND NEW.reviewed_user_id IS DISTINCT FROM OLD.reviewed_user_id
  THEN
    PERFORM public.refresh_user_rating(OLD.reviewed_user_id);
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_review_change() IS
  'Recalculates users.rating_average and rating_count after review insert/update/delete.';

DROP TRIGGER IF EXISTS trg_reviews_rating_aggregate ON public.reviews;
DROP TRIGGER IF EXISTS trg_handle_review_change ON public.reviews;
CREATE TRIGGER trg_reviews_rating_aggregate
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW
EXECUTE FUNCTION public.handle_review_change();

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
    v_reviewed := v_order.buyer_id;
    v_type := 'seller_to_buyer'::public.review_type_enum;
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

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reviews_insert_own ON public.reviews;
DROP POLICY IF EXISTS reviews_update_own_admin ON public.reviews;
DROP POLICY IF EXISTS reviews_select_all ON public.reviews;
DROP POLICY IF EXISTS reviews_delete_admin ON public.reviews;
DROP POLICY IF EXISTS reviews_select_visible ON public.reviews;
DROP POLICY IF EXISTS reviews_delete_admin_only ON public.reviews;

CREATE POLICY reviews_select_visible ON public.reviews
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY reviews_delete_admin_only ON public.reviews
  FOR DELETE TO authenticated
  USING (public.is_admin());

REVOKE ALL ON TABLE public.reviews FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.reviews TO anon, authenticated;
GRANT DELETE ON TABLE public.reviews TO authenticated;
GRANT ALL ON TABLE public.reviews TO postgres, service_role;

-- ===========================================================================
-- 4. Community reports
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.reports (
  report_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  reported_user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  order_id uuid REFERENCES public.orders (order_id) ON DELETE SET NULL,
  category text NOT NULL,
  details text NOT NULL,
  status public.report_status_enum NOT NULL DEFAULT 'under_review',
  admin_response text,
  reviewed_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reports_not_self CHECK (reporter_id <> reported_user_id),
  CONSTRAINT reports_category_check CHECK (category IN (
    'scam_or_fraud',
    'fake_product',
    'counterfeit_item',
    'harassment',
    'inappropriate_messages',
    'failure_to_ship',
    'item_not_as_described',
    'fake_identity',
    'other'
  )),
  CONSTRAINT reports_details_len CHECK (
    char_length(details) BETWEEN 10 AND 2000
  ),
  CONSTRAINT reports_admin_response_len CHECK (
    admin_response IS NULL OR char_length(admin_response) <= 2000
  )
);

COMMENT ON TABLE public.reports IS
  'Community reports against another user. Moderated in Supabase Studio. The reported user cannot read these rows.';

CREATE INDEX IF NOT EXISTS reports_reporter_created_idx
  ON public.reports (reporter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS reports_status_created_idx
  ON public.reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS reports_reported_user_idx
  ON public.reports (reported_user_id);

DROP TRIGGER IF EXISTS trg_reports_updated_at ON public.reports;
CREATE TRIGGER trg_reports_updated_at
BEFORE UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.report_evidence (
  report_evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.reports (report_id) ON DELETE CASCADE,
  file_path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT report_evidence_path_unique UNIQUE (file_path)
);

CREATE INDEX IF NOT EXISTS report_evidence_report_idx
  ON public.report_evidence (report_id);

CREATE OR REPLACE FUNCTION public.enforce_report_moderation_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.report_id := OLD.report_id;
  NEW.reporter_id := OLD.reporter_id;
  NEW.reported_user_id := OLD.reported_user_id;
  NEW.order_id := OLD.order_id;
  NEW.category := OLD.category;
  NEW.details := OLD.details;
  NEW.created_at := OLD.created_at;

  IF NEW.status IS DISTINCT FROM 'under_review'::public.report_status_enum
     AND OLD.status = 'under_review'::public.report_status_enum
  THEN
    NEW.resolved_at := COALESCE(NEW.resolved_at, now());
  END IF;

  IF NEW.status = 'under_review'::public.report_status_enum THEN
    NEW.resolved_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reports_moderation_guard ON public.reports;
CREATE TRIGGER trg_reports_moderation_guard
BEFORE UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.enforce_report_moderation_guard();

CREATE OR REPLACE FUNCTION public.notify_report_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'under_review'::public.report_status_enum
     AND NEW.status IS DISTINCT FROM 'under_review'::public.report_status_enum
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

DROP TRIGGER IF EXISTS trg_reports_notify_decision ON public.reports;
CREATE TRIGGER trg_reports_notify_decision
AFTER UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.notify_report_decision();

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

  v_details := btrim(COALESCE(p_details, ''));
  IF char_length(v_details) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please add a bit more detail.');
  END IF;
  IF char_length(v_details) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep your report under 2,000 characters.');
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
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.reports r
  WHERE r.reporter_id = v_uid
    AND r.created_at >= now() - interval '24 hours';

  IF v_recent >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Please wait before submitting another report.'
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_path := NULLIF(btrim(COALESCE(p_file_path, '')), '');
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

  IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report can no longer accept photos.');
  END IF;

  v_prefix := v_uid::text || '/' || p_report_id::text || '/';
  IF left(v_path, char_length(v_prefix)) IS DISTINCT FROM v_prefix THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo could not be attached.');
  END IF;

  IF lower(v_path) !~ '\.(jpe?g|png|webp)$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please upload a JPG, PNG, or WebP photo.');
  END IF;

  SELECT count(*) INTO v_count
  FROM public.report_evidence e
  WHERE e.report_id = p_report_id;

  IF v_count >= 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can attach up to 4 photos.');
  END IF;

  INSERT INTO public.report_evidence (report_id, file_path)
  VALUES (p_report_id, v_path)
  RETURNING report_evidence_id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'report_evidence_id', v_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'That photo is already attached.');
END;
$$;

REVOKE ALL ON FUNCTION public.submit_report(uuid, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.attach_report_evidence(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_report(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attach_report_evidence(uuid, text) TO authenticated;

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports FORCE ROW LEVEL SECURITY;
ALTER TABLE public.report_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_evidence FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reports_select_reporter_or_admin ON public.reports;
CREATE POLICY reports_select_reporter_or_admin ON public.reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS report_evidence_select_reporter_or_admin ON public.report_evidence;
CREATE POLICY report_evidence_select_reporter_or_admin ON public.report_evidence
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.reports r
      WHERE r.report_id = report_evidence.report_id
        AND (r.reporter_id = auth.uid() OR public.is_admin())
    )
  );

REVOKE ALL ON TABLE public.reports FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.report_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.reports TO authenticated;
GRANT SELECT ON TABLE public.report_evidence TO authenticated;
GRANT ALL ON TABLE public.reports TO postgres, service_role;
GRANT ALL ON TABLE public.report_evidence TO postgres, service_role;

-- ===========================================================================
-- 5. Private report-evidence bucket
-- ===========================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'report-evidence',
  'report-evidence',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS report_evidence_insert_own ON storage.objects;
CREATE POLICY report_evidence_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'report-evidence'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

DROP POLICY IF EXISTS report_evidence_select_own_or_admin ON storage.objects;
CREATE POLICY report_evidence_select_own_or_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'report-evidence'
    AND (
      split_part(name, '/', 1) = auth.uid()::text
      OR public.is_admin()
    )
  );

DROP POLICY IF EXISTS report_evidence_delete_own_or_admin ON storage.objects;
CREATE POLICY report_evidence_delete_own_or_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'report-evidence'
    AND (
      split_part(name, '/', 1) = auth.uid()::text
      OR public.is_admin()
    )
  );
