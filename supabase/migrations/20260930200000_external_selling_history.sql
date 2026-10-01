-- Optional past selling history on the existing seller application.
--
-- A claimed range is self-declared and is not the Successful Transactions score.
-- Only admin-verified external rows count, and at most 10 of them.
-- They are added to completed ThriftLine orders, then Table 13 is applied
-- by the existing trust_st_score function. Thresholds are unchanged.
--
-- Paste this file into the Supabase SQL editor and run it once.
-- Idempotent. Does not edit earlier migrations.

ALTER TABLE public.user_verifications
  ADD COLUMN IF NOT EXISTS claimed_selling_range text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_verifications_claimed_selling_range_check'
      AND conrelid = 'public.user_verifications'::regclass
  ) THEN
    ALTER TABLE public.user_verifications
      ADD CONSTRAINT user_verifications_claimed_selling_range_check
      CHECK (
        claimed_selling_range IS NULL
        OR claimed_selling_range IN (
          '1_10',
          '11_20',
          '21_30',
          '31_50',
          'above_50'
        )
      );
  END IF;
END
$$;

COMMENT ON COLUMN public.user_verifications.claimed_selling_range IS
  'Approximate previous selling experience declared by the applicant. Not used as the ST score.';

CREATE TABLE IF NOT EXISTS public.external_transactions (
  transaction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id uuid NOT NULL
    REFERENCES public.user_verifications (verification_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  platform text NOT NULL,
  item_name text NOT NULL,
  amount numeric,
  transaction_date date NOT NULL,
  listing_url text,
  review_status text NOT NULL DEFAULT 'pending',
  admin_review_note text,
  reviewed_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT external_transactions_platform_check CHECK (
    platform IN (
      'facebook_marketplace',
      'facebook_group',
      'instagram',
      'other'
    )
  ),
  CONSTRAINT external_transactions_item_len CHECK (
    char_length(btrim(item_name)) BETWEEN 2 AND 80
  ),
  CONSTRAINT external_transactions_amount_check CHECK (
    amount IS NULL OR (amount > 0 AND amount <= 10000000)
  ),
  CONSTRAINT external_transactions_date_check CHECK (
    transaction_date >= DATE '2010-01-01'
  ),
  CONSTRAINT external_transactions_url_len CHECK (
    listing_url IS NULL OR char_length(listing_url) <= 500
  ),
  CONSTRAINT external_transactions_status_check CHECK (
    review_status IN (
      'pending',
      'verified',
      'insufficient_evidence',
      'rejected'
    )
  ),
  CONSTRAINT external_transactions_note_len CHECK (
    admin_review_note IS NULL OR char_length(admin_review_note) <= 500
  )
);

CREATE INDEX IF NOT EXISTS external_transactions_verification_idx
  ON public.external_transactions (verification_id, created_at);

CREATE INDEX IF NOT EXISTS external_transactions_user_status_idx
  ON public.external_transactions (user_id, review_status);

CREATE TABLE IF NOT EXISTS public.external_transaction_evidence (
  evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL
    REFERENCES public.external_transactions (transaction_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  evidence_type text NOT NULL,
  storage_path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT external_evidence_type_check CHECK (
    evidence_type IN (
      'conversation',
      'payment',
      'delivery',
      'courier',
      'meetup',
      'acknowledgement',
      'feedback',
      'listing'
    )
  ),
  CONSTRAINT external_evidence_path_len CHECK (
    char_length(storage_path) BETWEEN 3 AND 500
  ),
  CONSTRAINT external_evidence_one_type_per_transaction
    UNIQUE (transaction_id, evidence_type)
);

CREATE INDEX IF NOT EXISTS external_transaction_evidence_tx_idx
  ON public.external_transaction_evidence (transaction_id);

CREATE OR REPLACE FUNCTION public.enforce_external_transaction_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  IF NEW.transaction_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'The transaction date cannot be in the future'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_verifications v
    WHERE v.verification_id = NEW.verification_id
      AND v.user_id = NEW.user_id
  ) THEN
    RAISE EXCEPTION 'This transaction does not belong to the application'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*)::integer
    INTO v_count
  FROM public.external_transactions t
  WHERE t.verification_id = NEW.verification_id
    AND t.transaction_id IS DISTINCT FROM NEW.transaction_id;

  IF v_count >= 10 THEN
    RAISE EXCEPTION 'A seller application can include at most 10 external transactions'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.review_status IS DISTINCT FROM 'pending'
     AND auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.is_admin()
     AND current_setting('thriftline.review_external', true) IS DISTINCT FROM '1'
  THEN
    RAISE EXCEPTION 'Only an admin can review external transaction evidence'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_external_transactions_rules
  ON public.external_transactions;
CREATE TRIGGER trg_external_transactions_rules
BEFORE INSERT OR UPDATE ON public.external_transactions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_external_transaction_rules();

CREATE OR REPLACE FUNCTION public.enforce_external_evidence_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid;
  v_count integer;
BEGIN
  SELECT t.user_id
    INTO v_owner
  FROM public.external_transactions t
  WHERE t.transaction_id = NEW.transaction_id;

  IF v_owner IS NULL OR v_owner IS DISTINCT FROM NEW.user_id THEN
    RAISE EXCEPTION 'Evidence does not belong to this transaction'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*)::integer
    INTO v_count
  FROM public.external_transaction_evidence e
  WHERE e.transaction_id = NEW.transaction_id
    AND e.evidence_id IS DISTINCT FROM NEW.evidence_id;

  IF v_count >= 2 THEN
    RAISE EXCEPTION 'Each external transaction can have 2 evidence photos'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_external_evidence_rules
  ON public.external_transaction_evidence;
CREATE TRIGGER trg_external_evidence_rules
BEFORE INSERT OR UPDATE ON public.external_transaction_evidence
FOR EACH ROW
EXECUTE FUNCTION public.enforce_external_evidence_rules();

ALTER TABLE public.external_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.external_transaction_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_transaction_evidence FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS external_transactions_select_own_or_admin
  ON public.external_transactions;
CREATE POLICY external_transactions_select_own_or_admin
  ON public.external_transactions
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS external_transactions_insert_own_pending
  ON public.external_transactions;
CREATE POLICY external_transactions_insert_own_pending
  ON public.external_transactions
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND review_status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM public.user_verifications v
      WHERE v.verification_id = external_transactions.verification_id
        AND v.user_id = auth.uid()
        AND v.verification_status = 'pending'::public.verification_status_enum
    )
  );

DROP POLICY IF EXISTS external_transactions_update_admin
  ON public.external_transactions;
CREATE POLICY external_transactions_update_admin
  ON public.external_transactions
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS external_transactions_delete_own_pending
  ON public.external_transactions;
CREATE POLICY external_transactions_delete_own_pending
  ON public.external_transactions
  FOR DELETE
  USING (
    auth.uid() = user_id
    AND review_status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM public.user_verifications v
      WHERE v.verification_id = external_transactions.verification_id
        AND v.user_id = auth.uid()
        AND v.verification_status = 'pending'::public.verification_status_enum
    )
  );

DROP POLICY IF EXISTS external_evidence_select_own_or_admin
  ON public.external_transaction_evidence;
CREATE POLICY external_evidence_select_own_or_admin
  ON public.external_transaction_evidence
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS external_evidence_insert_own_pending
  ON public.external_transaction_evidence;
CREATE POLICY external_evidence_insert_own_pending
  ON public.external_transaction_evidence
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.external_transactions t
      JOIN public.user_verifications v
        ON v.verification_id = t.verification_id
      WHERE t.transaction_id = external_transaction_evidence.transaction_id
        AND t.user_id = auth.uid()
        AND t.review_status = 'pending'
        AND v.verification_status = 'pending'::public.verification_status_enum
    )
  );

DROP POLICY IF EXISTS external_evidence_delete_own_pending
  ON public.external_transaction_evidence;
CREATE POLICY external_evidence_delete_own_pending
  ON public.external_transaction_evidence
  FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.external_transactions t
      WHERE t.transaction_id = external_transaction_evidence.transaction_id
        AND t.user_id = auth.uid()
        AND t.review_status = 'pending'
    )
  );

REVOKE ALL ON TABLE public.external_transactions FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.external_transaction_evidence FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.external_transactions TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.external_transaction_evidence TO authenticated;

-- ===========================================================================
-- Admin decision. Verified requires two different evidence types.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.review_external_transaction(
  p_transaction_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tx public.external_transactions%ROWTYPE;
  v_kinds integer;
  v_note text;
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.is_admin()
  THEN
    RAISE EXCEPTION 'only an admin can review external transaction evidence'
      USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('verified', 'insufficient_evidence', 'rejected') THEN
    RAISE EXCEPTION 'decision must be verified, insufficient_evidence, or rejected';
  END IF;

  SELECT *
    INTO v_tx
  FROM public.external_transactions
  WHERE transaction_id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'external transaction not found';
  END IF;

  IF p_decision = 'verified' THEN
    SELECT count(DISTINCT e.evidence_type)::integer
      INTO v_kinds
    FROM public.external_transaction_evidence e
    WHERE e.transaction_id = p_transaction_id;

    IF COALESCE(v_kinds, 0) < 2 THEN
      RAISE EXCEPTION 'Verify needs two different kinds of evidence';
    END IF;
  END IF;

  v_note := NULLIF(btrim(COALESCE(p_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 500 THEN
    RAISE EXCEPTION 'Keep the review note under 500 characters';
  END IF;

  PERFORM set_config('thriftline.review_external', '1', true);
  UPDATE public.external_transactions
  SET review_status = p_decision,
      admin_review_note = v_note,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE transaction_id = p_transaction_id;
  PERFORM set_config('thriftline.review_external', '0', true);
END;
$$;

REVOKE ALL ON FUNCTION public.review_external_transaction(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_external_transaction(uuid, text, text)
  TO authenticated, service_role, postgres;

CREATE OR REPLACE FUNCTION public.trg_external_transaction_trust()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.review_status IS NOT DISTINCT FROM OLD.review_status
     AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
  THEN
    RETURN NEW;
  END IF;
  PERFORM public.recalculate_seller_trust(NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_external_transactions_seller_trust
  ON public.external_transactions;
CREATE TRIGGER trg_external_transactions_seller_trust
AFTER UPDATE OF review_status ON public.external_transactions
FOR EACH ROW
EXECUTE FUNCTION public.trg_external_transaction_trust();

-- ===========================================================================
-- ST count: capped verified external evidence + completed ThriftLine orders.
-- Table 13 itself is still trust_st_score.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.recalculate_seller_trust(p_seller_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_ver public.user_verifications%ROWTYPE;
  v_has_ver boolean := false;
  v_government boolean := false;
  v_email boolean := false;
  v_phone boolean := false;
  v_face boolean := false;
  v_completed integer := 0;
  v_external integer := 0;
  v_eligible integer := 0;
  v_reports integer := 0;
  v_iv integer;
  v_st integer;
  v_ur integer;
  v_cr integer;
  v_ts integer;
  v_level text;
  v_breakdown jsonb;
BEGIN
  IF p_seller_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.seller_profiles sp
    WHERE sp.seller_id = p_seller_id
  ) THEN
    RETURN NULL;
  END IF;

  SELECT *
    INTO v_user
  FROM public.users
  WHERE user_id = p_seller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT *
    INTO v_ver
  FROM public.user_verifications
  WHERE user_id = p_seller_id
  ORDER BY COALESCE(reviewed_at, updated_at, submitted_at, created_at) DESC,
           verification_id DESC
  LIMIT 1;
  v_has_ver := FOUND;

  v_phone := COALESCE(v_user.is_phone_verified, false);
  IF v_has_ver THEN
    v_government :=
      v_ver.verification_status = 'approved'::public.verification_status_enum;
    v_email := COALESCE(v_ver.email_verified, false);
    v_phone := v_phone OR COALESCE(v_ver.phone_verified, false);
    v_face := v_government AND COALESCE(v_ver.liveness_passed, false);
  END IF;

  v_iv := public.trust_iv_score(v_government, v_email, v_phone, v_face);

  SELECT count(*)::integer
    INTO v_completed
  FROM public.orders o
  WHERE o.seller_id = p_seller_id
    AND o.order_status = 'completed'::public.order_status_enum
    AND NOT EXISTS (
      SELECT 1
      FROM public.escrow e
      WHERE e.order_id = o.order_id
        AND e.status IN (
          'refunded'::public.escrow_status_enum,
          'disputed'::public.escrow_status_enum
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = o.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    );

  SELECT LEAST(count(*)::integer, 10)
    INTO v_external
  FROM public.external_transactions t
  JOIN public.user_verifications v
    ON v.verification_id = t.verification_id
  WHERE t.user_id = p_seller_id
    AND t.review_status = 'verified'
    AND v.verification_status = 'approved'::public.verification_status_enum;

  v_eligible := v_external + v_completed;
  v_st := public.trust_st_score(v_eligible);
  v_ur := public.trust_ur_score(v_user.rating_average, v_user.rating_count);

  SELECT count(*)::integer
    INTO v_reports
  FROM public.reports r
  WHERE r.reported_user_id = p_seller_id
    AND r.status = 'action_taken'::public.report_status_enum;

  v_cr := public.trust_cr_score(v_reports);
  v_ts := public.trust_weighted_sum(v_iv, v_st, v_ur, v_cr);
  v_level := public.trust_level_for(v_ts);
  v_breakdown := jsonb_build_object(
    'iv', v_iv,
    'st', v_st,
    'ur', v_ur,
    'cr', v_cr,
    'weights', jsonb_build_object(
      'iv', 0.40,
      'st', 0.30,
      'ur', 0.20,
      'cr', 0.10
    ),
    'completed_orders', v_eligible,
    'verified_external', v_external,
    'completed_thriftline', v_completed,
    'eligible_transactions', v_eligible,
    'confirmed_reports', v_reports,
    'rating_count', COALESCE(v_user.rating_count, 0),
    'formula', '2.3.2'
  );

  IF v_user.trust_score IS NOT DISTINCT FROM v_ts::numeric
     AND v_user.trust_level IS NOT DISTINCT FROM v_level
     AND v_user.trust_breakdown IS NOT DISTINCT FROM v_breakdown
  THEN
    RETURN v_ts;
  END IF;

  PERFORM set_config('thriftline.maintain_trust', '1', true);
  BEGIN
    UPDATE public.users
    SET trust_score = v_ts,
        trust_level = v_level,
        trust_breakdown = v_breakdown,
        trust_updated_at = now()
    WHERE user_id = p_seller_id;
    PERFORM set_config('thriftline.maintain_trust', '0', true);
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM set_config('thriftline.maintain_trust', '0', true);
      RAISE;
  END;

  RETURN v_ts;
END;
$$;

COMMENT ON FUNCTION public.recalculate_seller_trust(uuid) IS
  'Recomputes seller trust. ST uses at most 10 verified external transactions plus completed ThriftLine orders, then Table 13.';

DO $$
DECLARE
  v_seller uuid;
BEGIN
  FOR v_seller IN
    SELECT sp.seller_id
    FROM public.seller_profiles sp
  LOOP
    PERFORM public.recalculate_seller_trust(v_seller);
  END LOOP;
END
$$;
