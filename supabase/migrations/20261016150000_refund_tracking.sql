-- Buyer refund tracking: PayMongo first, manual GCash fallback.
--
-- escrow.status = 'refunded' keeps its meaning: the refund was decided and the
-- funds are no longer seller earnings. escrow.refund_state tracks whether the
-- buyer actually has the money. payments.payment_status becomes 'refunded'
-- only when the return is confirmed (PayMongo succeeded or a recorded manual
-- GCash transfer).
--
-- Buyer GCash details and the QR Ph claim link live in escrow_refund_details,
-- which sellers cannot read. Every provider call is logged in
-- escrow_refund_attempts (admin read only).
--
-- Does not rewrite previously applied migrations.

-- ===========================================================================
-- 1. Types, columns, tables
-- ===========================================================================

DO $$
BEGIN
  CREATE TYPE public.escrow_refund_state_enum AS ENUM (
    'provider_pending',
    'awaiting_buyer_claim',
    'succeeded',
    'manual_required',
    'manual_completed'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

ALTER TABLE public.escrow
  ADD COLUMN IF NOT EXISTS refund_state public.escrow_refund_state_enum,
  ADD COLUMN IF NOT EXISTS refund_provider_error text,
  ADD COLUMN IF NOT EXISTS refund_last_checked_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_completed_at timestamptz;

CREATE INDEX IF NOT EXISTS escrow_refund_state_idx
  ON public.escrow (refund_state)
  WHERE refund_state IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.escrow_refund_details (
  escrow_id uuid PRIMARY KEY REFERENCES public.escrow (escrow_id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  transfer_link text,
  transfer_link_expires_at timestamptz,
  gcash_account_name text,
  gcash_mobile_number text,
  gcash_submitted_at timestamptz,
  manual_amount_centavos integer,
  manual_reference text,
  manual_sent_at timestamptz,
  manual_evidence_path text,
  manual_note text,
  manual_recorded_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  manual_recorded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT escrow_refund_details_gcash_name_chk CHECK (
    gcash_account_name IS NULL
    OR char_length(btrim(gcash_account_name)) BETWEEN 2 AND 80
  ),
  CONSTRAINT escrow_refund_details_gcash_mobile_chk CHECK (
    gcash_mobile_number IS NULL
    OR gcash_mobile_number ~ '^09[0-9]{9}$'
  ),
  CONSTRAINT escrow_refund_details_manual_amount_chk CHECK (
    manual_amount_centavos IS NULL OR manual_amount_centavos > 0
  )
);

COMMENT ON TABLE public.escrow_refund_details IS
  'Private refund details for the buyer and admins only: QR Ph claim link, buyer GCash for manual refunds, and the recorded manual transfer.';

DROP TRIGGER IF EXISTS trg_escrow_refund_details_updated_at
  ON public.escrow_refund_details;
CREATE TRIGGER trg_escrow_refund_details_updated_at
BEFORE UPDATE ON public.escrow_refund_details
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.escrow_refund_attempts (
  attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  escrow_id uuid NOT NULL REFERENCES public.escrow (escrow_id) ON DELETE CASCADE,
  source text NOT NULL,
  action text NOT NULL,
  outcome text NOT NULL,
  paymongo_refund_id text,
  http_status integer,
  provider_status text,
  error_code text,
  has_transfer_link boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT escrow_refund_attempts_source_chk CHECK (
    source IN ('admin_dispute', 'fulfillment_sla', 'admin_retry', 'reconcile', 'webhook')
  ),
  CONSTRAINT escrow_refund_attempts_action_chk CHECK (
    action IN ('create', 'adopt', 'retrieve', 'lookup', 'webhook')
  ),
  CONSTRAINT escrow_refund_attempts_outcome_chk CHECK (
    outcome IN ('accepted', 'rejected', 'unknown', 'updated', 'not_found')
  )
);

CREATE INDEX IF NOT EXISTS escrow_refund_attempts_escrow_idx
  ON public.escrow_refund_attempts (escrow_id, created_at DESC);

COMMENT ON TABLE public.escrow_refund_attempts IS
  'Audit log of every PayMongo refund call or status update for an escrow. Admin read only.';

ALTER TABLE public.escrow_refund_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_refund_details FORCE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_refund_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_refund_attempts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS escrow_refund_details_select_buyer_admin
  ON public.escrow_refund_details;
CREATE POLICY escrow_refund_details_select_buyer_admin
  ON public.escrow_refund_details
  FOR SELECT TO authenticated
  USING (buyer_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS escrow_refund_details_write_postgres
  ON public.escrow_refund_details;
CREATE POLICY escrow_refund_details_write_postgres
  ON public.escrow_refund_details
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS escrow_refund_attempts_select_admin
  ON public.escrow_refund_attempts;
CREATE POLICY escrow_refund_attempts_select_admin
  ON public.escrow_refund_attempts
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS escrow_refund_attempts_write_postgres
  ON public.escrow_refund_attempts;
CREATE POLICY escrow_refund_attempts_write_postgres
  ON public.escrow_refund_attempts
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.escrow_refund_details FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.escrow_refund_attempts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.escrow_refund_details TO authenticated;
GRANT SELECT ON TABLE public.escrow_refund_attempts TO authenticated;
GRANT ALL ON TABLE public.escrow_refund_details TO postgres, service_role;
GRANT ALL ON TABLE public.escrow_refund_attempts TO postgres, service_role;

-- ===========================================================================
-- 2. Truthful backfill of existing refunds
-- ===========================================================================

UPDATE public.escrow
SET refund_state = CASE
      WHEN refund_provider = 'paymongo'::public.escrow_refund_provider_enum
        AND lower(coalesce(refund_provider_status, '')) = 'succeeded'
        THEN 'succeeded'::public.escrow_refund_state_enum
      WHEN refund_provider = 'paymongo'::public.escrow_refund_provider_enum
        THEN 'provider_pending'::public.escrow_refund_state_enum
      ELSE 'manual_required'::public.escrow_refund_state_enum
    END,
    refund_completed_at = CASE
      WHEN refund_provider = 'paymongo'::public.escrow_refund_provider_enum
        AND lower(coalesce(refund_provider_status, '')) = 'succeeded'
        THEN refunded_at
      ELSE refund_completed_at
    END
WHERE status = 'refunded'::public.escrow_status_enum
  AND refund_state IS NULL;

-- A payment is only "refunded" once the money is confirmed returned.
UPDATE public.payments p
SET payment_status = 'paid'::public.payment_status_enum
FROM public.escrow e
WHERE e.payment_id = p.payment_id
  AND e.status = 'refunded'::public.escrow_status_enum
  AND e.refund_state IN (
    'provider_pending'::public.escrow_refund_state_enum,
    'manual_required'::public.escrow_refund_state_enum
  )
  AND p.payment_status = 'refunded'::public.payment_status_enum;

INSERT INTO public.escrow_refund_details (escrow_id, buyer_id)
SELECT e.escrow_id, e.buyer_id
FROM public.escrow e
WHERE e.status = 'refunded'::public.escrow_status_enum
ON CONFLICT (escrow_id) DO NOTHING;

ALTER TABLE public.escrow
  DROP CONSTRAINT IF EXISTS escrow_refunded_has_state_chk;
ALTER TABLE public.escrow
  ADD CONSTRAINT escrow_refunded_has_state_chk
  CHECK (
    status IS DISTINCT FROM 'refunded'::public.escrow_status_enum
    OR refund_state IS NOT NULL
  );

-- ===========================================================================
-- 3. Internal helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION public._is_service_role()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(auth.jwt() ->> 'role', auth.role()) = 'service_role';
$$;

CREATE OR REPLACE FUNCTION public._peso_text(p_centavos integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '₱' || to_char(COALESCE(p_centavos, 0) / 100.0, 'FM999,999,990.00');
$$;

-- Resolve the refund state from a verified provider outcome.
CREATE OR REPLACE FUNCTION public._resolve_refund_state(
  p_provider text,
  p_provider_status text,
  p_transfer_link text
)
RETURNS public.escrow_refund_state_enum
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN lower(coalesce(p_provider, '')) <> 'paymongo'
      THEN 'manual_required'::public.escrow_refund_state_enum
    WHEN lower(coalesce(p_provider_status, '')) = 'succeeded'
      THEN 'succeeded'::public.escrow_refund_state_enum
    WHEN lower(coalesce(p_provider_status, '')) = 'failed'
      THEN 'manual_required'::public.escrow_refund_state_enum
    WHEN NULLIF(btrim(coalesce(p_transfer_link, '')), '') IS NOT NULL
      THEN 'awaiting_buyer_claim'::public.escrow_refund_state_enum
    ELSE 'provider_pending'::public.escrow_refund_state_enum
  END;
$$;

CREATE OR REPLACE FUNCTION public._notify_refund_buyer(
  p_escrow public.escrow,
  p_state public.escrow_refund_state_enum
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_number text;
  v_amount text := public._peso_text(p_escrow.amount_centavos);
  v_title text;
  v_body text;
BEGIN
  SELECT COALESCE(o.order_number, '') INTO v_number
  FROM public.orders o
  WHERE o.order_id = p_escrow.order_id;

  CASE p_state
    WHEN 'succeeded' THEN
      v_title := 'Refund completed';
      v_body := 'PayMongo confirmed your ' || v_amount || ' refund for Order #' ||
        v_number || '.';
    WHEN 'provider_pending' THEN
      v_title := 'Refund in progress';
      v_body := 'PayMongo is processing your ' || v_amount || ' refund for Order #' ||
        v_number || '. We will tell you when it is completed.';
    WHEN 'awaiting_buyer_claim' THEN
      v_title := 'Action needed: claim your refund';
      v_body := 'Your ' || v_amount || ' refund for Order #' || v_number ||
        ' is ready to claim. Open Transaction History and use the PayMongo claim link before it expires.';
    WHEN 'manual_required' THEN
      v_title := 'Refund needs your GCash details';
      v_body := 'The automatic refund for Order #' || v_number ||
        ' could not be completed. Open Transaction History and add your GCash details so our team can send ' ||
        v_amount || ' to you.';
    WHEN 'manual_completed' THEN
      v_title := 'Refund sent to your GCash';
      v_body := 'Our team sent your ' || v_amount || ' refund for Order #' || v_number ||
        ' to your GCash.';
  END CASE;

  PERFORM public.notify_user(
    p_escrow.buyer_id,
    'orderConfirmed',
    v_title,
    v_body,
    jsonb_build_object(
      'order_id', p_escrow.order_id,
      'escrow_id', p_escrow.escrow_id,
      'refund_state', p_state::text
    ),
    'buyer'::public.notification_audience_enum
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._notify_refund_admins(
  p_escrow public.escrow,
  p_title text,
  p_body text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin uuid;
BEGIN
  FOR v_admin IN
    SELECT u.user_id
    FROM public.users u
    WHERE u.role IN ('admin'::public.user_role_enum, 'super_admin'::public.user_role_enum)
      AND u.account_status = 'active'
  LOOP
    PERFORM public.notify_user(
      v_admin,
      'system',
      p_title,
      p_body,
      jsonb_build_object(
        'order_id', p_escrow.order_id,
        'escrow_id', p_escrow.escrow_id,
        'refund_action', true
      ),
      'system'::public.notification_audience_enum
    );
  END LOOP;
END;
$$;

-- Records the refund decision on a locked held/disputed escrow.
-- Returns the resulting refund state, or NULL if the escrow was not updated.
CREATE OR REPLACE FUNCTION public._record_escrow_refund_decision(
  p_escrow_id uuid,
  p_provider text,
  p_paymongo_refund_id text,
  p_provider_status text,
  p_transfer_link text,
  p_transfer_link_expires_at timestamptz,
  p_provider_error text,
  p_default_reason text
)
RETURNS public.escrow_refund_state_enum
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_state public.escrow_refund_state_enum;
  v_escrow public.escrow%ROWTYPE;
  v_link text := NULLIF(btrim(coalesce(p_transfer_link, '')), '');
BEGIN
  v_state := public._resolve_refund_state(v_provider, p_provider_status, v_link);

  UPDATE public.escrow
  SET
    status = 'refunded'::public.escrow_status_enum,
    refunded_at = now(),
    refund_reason = COALESCE(refund_reason, p_default_reason),
    refund_lock_at = NULL,
    refund_provider = v_provider::public.escrow_refund_provider_enum,
    paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    refund_provider_status = COALESCE(
      NULLIF(btrim(coalesce(p_provider_status, '')), ''),
      v_provider
    ),
    refund_state = v_state,
    refund_provider_error = NULLIF(btrim(coalesce(p_provider_error, '')), ''),
    refund_last_checked_at = now(),
    refund_completed_at = CASE
      WHEN v_state = 'succeeded'::public.escrow_refund_state_enum THEN now()
      ELSE NULL
    END
  WHERE escrow_id = p_escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
  RETURNING * INTO v_escrow;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, transfer_link, transfer_link_expires_at
  )
  VALUES (
    v_escrow.escrow_id,
    v_escrow.buyer_id,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN v_link ELSE NULL END,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN p_transfer_link_expires_at ELSE NULL END
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET transfer_link = EXCLUDED.transfer_link,
      transfer_link_expires_at = EXCLUDED.transfer_link_expires_at;

  IF v_state = 'succeeded'::public.escrow_refund_state_enum THEN
    UPDATE public.payments
    SET payment_status = 'refunded'::public.payment_status_enum
    WHERE payment_id = v_escrow.payment_id
      AND payment_status = 'paid'::public.payment_status_enum;
  END IF;

  IF v_state = 'manual_required'::public.escrow_refund_state_enum THEN
    PERFORM public._notify_refund_admins(
      v_escrow,
      'Manual refund needed',
      'A PayMongo refund could not be completed. Review the order and send the buyer ' ||
        public._peso_text(v_escrow.amount_centavos) || ' through GCash.'
    );
  END IF;

  RETURN v_state;
END;
$$;

REVOKE ALL ON FUNCTION public._is_service_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._is_service_role() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._resolve_refund_state(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._resolve_refund_state(text, text, text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._notify_refund_buyer(public.escrow, public.escrow_refund_state_enum)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._notify_refund_admins(public.escrow, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._record_escrow_refund_decision(
  uuid, text, text, text, text, timestamptz, text, text
) FROM PUBLIC, anon, authenticated;

-- ===========================================================================
-- 4. Prepare functions: concurrency guard + channel for endpoint selection
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.prepare_delivery_refund(
  p_dispute_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_note text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_payment public.payments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can refund this payment.'
    );
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 2,000 characters.');
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  PERFORM public.ensure_order_escrow_hold(v_order.order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'refund_state', v_escrow.refund_state::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL
     AND v_escrow.refund_lock_at > now() - interval '2 minutes' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A refund for this order is already being processed. Try again in a moment.'
    );
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE payment_id = v_escrow.payment_id
  FOR UPDATE;

  UPDATE public.escrow
  SET
    refund_lock_at = now(),
    refund_reason = COALESCE(v_note, refund_reason, 'admin_refund'),
    resolved_by = v_uid,
    dispute_id = v_dispute.dispute_id
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'needs_provider_refund', true,
    'dispute_id', v_dispute.dispute_id,
    'order_id', v_order.order_id,
    'escrow_id', v_escrow.escrow_id,
    'amount_centavos', v_escrow.amount_centavos,
    'paymongo_payment_id', v_payment.paymongo_payment_id,
    'paymongo_channel', v_payment.paymongo_channel,
    'admin_note', v_note
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_fulfillment_sla_refund(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_payment public.payments%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF NOT public.order_is_stuck_preparing(p_order_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order is no longer waiting on the seller.');
  END IF;

  IF public.order_paid_at(p_order_id) > now() - interval '72 hours' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auto-cancel is not due yet.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = p_order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'An open delivery dispute must be reviewed first.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reports r
    WHERE r.order_id = p_order_id
      AND r.status IN (
        'under_review'::public.report_status_enum,
        'needs_more_evidence'::public.report_status_enum
      )
      AND r.category IS DISTINCT FROM 'seller_not_processing_order'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Another open report must be reviewed first.');
  END IF;

  PERFORM public.ensure_order_escrow_hold(v_order.order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'refund_state', v_escrow.refund_state::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL
     AND v_escrow.refund_lock_at > now() - interval '2 minutes' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A refund for this order is already being processed.'
    );
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE payment_id = v_escrow.payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  UPDATE public.escrow
  SET
    refund_lock_at = now(),
    refund_reason = COALESCE(refund_reason, 'fulfillment_sla')
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'needs_provider_refund', true,
    'order_id', v_order.order_id,
    'escrow_id', v_escrow.escrow_id,
    'amount_centavos', v_escrow.amount_centavos,
    'paymongo_payment_id', v_payment.paymongo_payment_id,
    'paymongo_channel', v_payment.paymongo_channel
  );
END;
$$;

-- ===========================================================================
-- 5. Finalize functions (signature gains link/expiry/error parameters)
-- ===========================================================================

DROP FUNCTION IF EXISTS public.finalize_delivery_refund(uuid, text, text, text, text);

CREATE OR REPLACE FUNCTION public.finalize_delivery_refund(
  p_dispute_id uuid,
  p_provider text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_admin_note text DEFAULT NULL,
  p_transfer_link text DEFAULT NULL,
  p_transfer_link_expires_at timestamptz DEFAULT NULL,
  p_provider_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_provider text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_note text;
  v_state public.escrow_refund_state_enum;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can refund this payment.');
  END IF;

  v_provider := lower(trim(coalesce(p_provider, '')));
  IF v_provider NOT IN ('paymongo', 'internal') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown refund provider.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'refund_state', v_escrow.refund_state::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);

  UPDATE public.escrow
  SET resolved_by = v_uid,
      dispute_id = v_dispute.dispute_id,
      refund_reason = COALESCE(v_note, refund_reason)
  WHERE escrow_id = v_escrow.escrow_id;

  v_state := public._record_escrow_refund_decision(
    v_escrow.escrow_id,
    v_provider,
    p_paymongo_refund_id,
    p_provider_status,
    p_transfer_link,
    p_transfer_link_expires_at,
    p_provider_error,
    'admin_refund'
  );

  IF v_state IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record this refund.');
  END IF;

  UPDATE public.shipments
  SET
    delivery_status = 'cancelled'::public.delivery_status_enum,
    completion_reason = COALESCE(completion_reason, 'admin_refunded_payment'),
    completed_at = COALESCE(completed_at, now())
  WHERE order_id = v_order.order_id
    AND delivery_status IS DISTINCT FROM 'cancelled'::public.delivery_status_enum;

  UPDATE public.orders
  SET order_status = 'cancelled'::public.order_status_enum,
      updated_at = now()
  WHERE order_id = v_order.order_id
    AND order_status IS DISTINCT FROM 'cancelled'::public.order_status_enum;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
  PERFORM public._notify_refund_buyer(v_escrow, v_state);

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Payment refunded',
    'The held payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' was refunded to the buyer and is not available as earnings.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  INSERT INTO public.admin_audit_logs (
    category, event_type, status, summary, actor_user_id, target_type, target_id, details
  )
  VALUES (
    'payments_escrow',
    'buyer_refund_decided',
    'success',
    'Refund decided for Order #' || COALESCE(v_order.order_number, '') ||
      ' (' || v_state::text || ')',
    v_uid,
    'order',
    v_order.order_id::text,
    jsonb_build_object(
      'escrow_id', v_escrow.escrow_id,
      'refund_provider', v_provider,
      'refund_state', v_state::text,
      'paymongo_refund_id', v_escrow.paymongo_refund_id,
      'amount_centavos', v_escrow.amount_centavos
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'refund',
    'status', 'refunded',
    'refund_provider', v_provider,
    'refund_state', v_state::text,
    'amount_centavos', v_escrow.amount_centavos
  );
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_delivery_refund(
  uuid, text, text, text, text, text, timestamptz, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_delivery_refund(
  uuid, text, text, text, text, text, timestamptz, text
) TO authenticated;

DROP FUNCTION IF EXISTS public.finalize_fulfillment_sla_refund(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.finalize_fulfillment_sla_refund(
  p_order_id uuid,
  p_provider text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_transfer_link text DEFAULT NULL,
  p_transfer_link_expires_at timestamptz DEFAULT NULL,
  p_provider_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider text;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_violation jsonb;
  v_notify boolean := false;
  v_state public.escrow_refund_state_enum;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  v_provider := lower(trim(coalesce(p_provider, '')));
  IF v_provider NOT IN ('paymongo', 'internal') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown refund provider.');
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    INSERT INTO public.fulfillment_sla_events (order_id, event_key)
    VALUES (p_order_id, 'auto_cancel_72h')
    ON CONFLICT DO NOTHING;
    v_violation := public.record_fulfillment_sla_violation(p_order_id);
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'refund_state', v_escrow.refund_state::text,
      'amount_centavos', v_escrow.amount_centavos,
      'violation_report_id', v_violation ->> 'report_id'
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  v_state := public._record_escrow_refund_decision(
    v_escrow.escrow_id,
    v_provider,
    p_paymongo_refund_id,
    p_provider_status,
    p_transfer_link,
    p_transfer_link_expires_at,
    p_provider_error,
    'fulfillment_sla'
  );

  IF v_state IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record this refund.');
  END IF;

  UPDATE public.shipments
  SET
    delivery_status = 'cancelled'::public.delivery_status_enum,
    completion_reason = COALESCE(completion_reason, 'fulfillment_sla_auto_cancel'),
    completed_at = COALESCE(completed_at, now())
  WHERE order_id = v_order.order_id
    AND delivery_status IS DISTINCT FROM 'cancelled'::public.delivery_status_enum;

  UPDATE public.orders
  SET order_status = 'cancelled'::public.order_status_enum,
      updated_at = now()
  WHERE order_id = v_order.order_id
    AND order_status IS DISTINCT FROM 'cancelled'::public.order_status_enum;

  INSERT INTO public.fulfillment_sla_events (order_id, event_key)
  VALUES (p_order_id, 'auto_cancel_72h')
  ON CONFLICT DO NOTHING;
  v_notify := FOUND;

  v_violation := public.record_fulfillment_sla_violation(p_order_id);

  IF v_notify THEN
    PERFORM public.notify_user(
      v_order.buyer_id,
      'orderConfirmed',
      'Order cancelled',
      'Your order was cancelled because the seller did not process it before the deadline. ' ||
        'We will send a separate update on your refund.',
      jsonb_build_object(
        'order_id', v_order.order_id,
        'event', 'fulfillment_auto_cancel',
        'refund_provider', v_provider,
        'refund_state', v_state::text
      ),
      'buyer'::public.notification_audience_enum
    );
    SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
    PERFORM public._notify_refund_buyer(v_escrow, v_state);
    PERFORM public.notify_user(
      v_order.seller_id,
      'system',
      'Order automatically cancelled',
      'An order was automatically cancelled because it was not processed before the deadline. A confirmed fulfillment violation has been recorded.',
      jsonb_build_object(
        'order_id', v_order.order_id,
        'event', 'fulfillment_auto_cancel',
        'report_id', v_violation ->> 'report_id'
      ),
      'seller'::public.notification_audience_enum
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'refund',
    'status', 'refunded',
    'refund_provider', v_provider,
    'refund_state', v_state::text,
    'amount_centavos', v_escrow.amount_centavos,
    'violation_report_id', v_violation ->> 'report_id'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_fulfillment_sla_refund(
  uuid, text, text, text, text, timestamptz, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_fulfillment_sla_refund(
  uuid, text, text, text, text, timestamptz, text
) TO postgres, service_role;

-- ===========================================================================
-- 6. Attempt log, provider updates, retry, lock clearing
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.record_refund_attempt(
  p_escrow_id uuid,
  p_source text,
  p_action text,
  p_outcome text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_http_status integer DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_error_code text DEFAULT NULL,
  p_has_transfer_link boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public._is_service_role() AND NOT (auth.uid() IS NOT NULL AND public.is_admin()) THEN
    RAISE EXCEPTION 'Not allowed.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.escrow_refund_attempts (
    escrow_id, source, action, outcome, paymongo_refund_id, http_status,
    provider_status, error_code, has_transfer_link, created_by
  )
  VALUES (
    p_escrow_id,
    p_source,
    p_action,
    p_outcome,
    NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    p_http_status,
    NULLIF(left(btrim(coalesce(p_provider_status, '')), 80), ''),
    NULLIF(left(btrim(coalesce(p_error_code, '')), 120), ''),
    COALESCE(p_has_transfer_link, false),
    auth.uid()
  )
  RETURNING attempt_id INTO v_id;

  RETURN v_id;
END;
$$;

-- Applies a verified PayMongo refund status (webhook, reconcile, admin check).
CREATE OR REPLACE FUNCTION public.apply_refund_provider_update(
  p_paymongo_refund_id text,
  p_provider_status text,
  p_transfer_link text DEFAULT NULL,
  p_transfer_link_expires_at timestamptz DEFAULT NULL,
  p_provider_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_escrow public.escrow%ROWTYPE;
  v_status text := lower(btrim(coalesce(p_provider_status, '')));
  v_link text := NULLIF(btrim(coalesce(p_transfer_link, '')), '');
  v_next public.escrow_refund_state_enum;
BEGIN
  IF NOT public._is_service_role() AND NOT (auth.uid() IS NOT NULL AND public.is_admin()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), '')
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', true, 'ignored', true, 'reason', 'unknown_refund');
  END IF;

  IF v_escrow.refund_state IN (
    'succeeded'::public.escrow_refund_state_enum,
    'manual_completed'::public.escrow_refund_state_enum
  ) OR v_escrow.refund_state IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'ignored', true,
      'refund_state', v_escrow.refund_state::text
    );
  END IF;

  IF v_status = 'succeeded' THEN
    v_next := 'succeeded';
  ELSIF v_status = 'failed' THEN
    v_next := 'manual_required';
  ELSIF v_escrow.refund_state = 'manual_required'::public.escrow_refund_state_enum THEN
    -- A failed refund stays manual unless a retry attaches a new refund id.
    v_next := 'manual_required';
  ELSIF v_link IS NOT NULL
     OR v_escrow.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum THEN
    v_next := 'awaiting_buyer_claim';
  ELSE
    v_next := 'provider_pending';
  END IF;

  UPDATE public.escrow
  SET refund_state = v_next,
      refund_provider_status = COALESCE(NULLIF(v_status, ''), refund_provider_status),
      refund_provider_error = CASE
        WHEN v_next = 'manual_required'
          THEN COALESCE(NULLIF(btrim(coalesce(p_provider_error, '')), ''), 'provider_failed')
        ELSE refund_provider_error
      END,
      refund_last_checked_at = now(),
      refund_completed_at = CASE
        WHEN v_next = 'succeeded' THEN COALESCE(refund_completed_at, now())
        ELSE refund_completed_at
      END
  WHERE escrow_id = v_escrow.escrow_id;

  IF v_link IS NOT NULL THEN
    INSERT INTO public.escrow_refund_details (
      escrow_id, buyer_id, transfer_link, transfer_link_expires_at
    )
    VALUES (v_escrow.escrow_id, v_escrow.buyer_id, v_link, p_transfer_link_expires_at)
    ON CONFLICT (escrow_id) DO UPDATE
    SET transfer_link = EXCLUDED.transfer_link,
        transfer_link_expires_at = COALESCE(
          EXCLUDED.transfer_link_expires_at,
          public.escrow_refund_details.transfer_link_expires_at
        );
  END IF;

  IF v_next = 'manual_required' THEN
    UPDATE public.escrow_refund_details
    SET transfer_link = NULL,
        transfer_link_expires_at = NULL
    WHERE escrow_id = v_escrow.escrow_id;
  END IF;

  IF v_next = 'succeeded' THEN
    UPDATE public.payments
    SET payment_status = 'refunded'::public.payment_status_enum
    WHERE payment_id = v_escrow.payment_id
      AND payment_status = 'paid'::public.payment_status_enum;
  END IF;

  IF v_next IS DISTINCT FROM v_escrow.refund_state THEN
    SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
    PERFORM public._notify_refund_buyer(v_escrow, v_next);
    IF v_next = 'manual_required' THEN
      PERFORM public._notify_refund_admins(
        v_escrow,
        'Manual refund needed',
        'PayMongo reported a failed refund. Review the order and send the buyer ' ||
          public._peso_text(v_escrow.amount_centavos) || ' through GCash, or retry PayMongo.'
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'escrow_id', v_escrow.escrow_id,
    'refund_state', v_next::text
  );
END;
$$;

-- Admin starts a new PayMongo attempt for a refund that needs manual action.
CREATE OR REPLACE FUNCTION public.prepare_refund_retry(p_escrow_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_escrow public.escrow%ROWTYPE;
  v_payment public.payments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can retry this refund.');
  END IF;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = p_escrow_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Refund not found.');
  END IF;

  IF v_escrow.status IS DISTINCT FROM 'refunded'::public.escrow_status_enum
     OR v_escrow.refund_state IS DISTINCT FROM 'manual_required'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only refunds that need action can be retried through PayMongo.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The last PayMongo attempt has an unconfirmed result. Check PayMongo status first.'
    );
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE payment_id = v_escrow.payment_id;

  IF v_payment.paymongo_payment_id IS NULL
     OR v_payment.paymongo_payment_id NOT LIKE 'pay\_%' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment has no PayMongo payment id. Record a manual GCash refund instead.'
    );
  END IF;

  UPDATE public.escrow SET refund_lock_at = now() WHERE escrow_id = v_escrow.escrow_id;

  RETURN jsonb_build_object(
    'success', true,
    'escrow_id', v_escrow.escrow_id,
    'order_id', v_escrow.order_id,
    'amount_centavos', v_escrow.amount_centavos,
    'paymongo_payment_id', v_payment.paymongo_payment_id,
    'paymongo_channel', v_payment.paymongo_channel,
    'previous_refund_id', v_escrow.paymongo_refund_id
  );
END;
$$;

-- Result of a retry (or adoption of an existing PayMongo refund).
-- outcome: accepted | rejected | unknown
CREATE OR REPLACE FUNCTION public.apply_refund_retry_result(
  p_escrow_id uuid,
  p_outcome text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_transfer_link text DEFAULT NULL,
  p_transfer_link_expires_at timestamptz DEFAULT NULL,
  p_provider_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_escrow public.escrow%ROWTYPE;
  v_outcome text := lower(btrim(coalesce(p_outcome, '')));
  v_state public.escrow_refund_state_enum;
  v_link text := NULLIF(btrim(coalesce(p_transfer_link, '')), '');
  v_refund_id text := NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), '');
BEGIN
  IF NOT public._is_service_role() AND NOT (auth.uid() IS NOT NULL AND public.is_admin()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = p_escrow_id FOR UPDATE;
  IF NOT FOUND OR v_escrow.status IS DISTINCT FROM 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Refund not found.');
  END IF;

  IF v_escrow.refund_state IN (
    'succeeded'::public.escrow_refund_state_enum,
    'manual_completed'::public.escrow_refund_state_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_completed', true,
      'refund_state', v_escrow.refund_state::text
    );
  END IF;

  IF v_outcome = 'unknown' THEN
    UPDATE public.escrow
    SET refund_lock_at = COALESCE(refund_lock_at, now()),
        refund_provider_error = 'unknown_outcome',
        refund_last_checked_at = now()
    WHERE escrow_id = v_escrow.escrow_id;
    RETURN jsonb_build_object(
      'success', true,
      'refund_state', v_escrow.refund_state::text,
      'unverified', true
    );
  END IF;

  IF v_outcome = 'rejected' THEN
    UPDATE public.escrow
    SET refund_lock_at = NULL,
        refund_state = 'manual_required',
        refund_provider_error = COALESCE(
          NULLIF(btrim(coalesce(p_provider_error, '')), ''),
          'provider_rejected'
        ),
        refund_last_checked_at = now()
    WHERE escrow_id = v_escrow.escrow_id;
    RETURN jsonb_build_object('success', true, 'refund_state', 'manual_required');
  END IF;

  IF v_outcome IS DISTINCT FROM 'accepted' OR v_refund_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown refund result.');
  END IF;

  v_state := public._resolve_refund_state('paymongo', p_provider_status, v_link);

  UPDATE public.escrow
  SET refund_lock_at = NULL,
      refund_provider = 'paymongo'::public.escrow_refund_provider_enum,
      paymongo_refund_id = v_refund_id,
      refund_provider_status = COALESCE(
        NULLIF(lower(btrim(coalesce(p_provider_status, ''))), ''),
        'pending'
      ),
      refund_state = v_state,
      refund_provider_error = CASE
        WHEN v_state = 'manual_required' THEN 'provider_failed'
        ELSE NULL
      END,
      refund_last_checked_at = now(),
      refund_completed_at = CASE
        WHEN v_state = 'succeeded' THEN now()
        ELSE NULL
      END
  WHERE escrow_id = v_escrow.escrow_id;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, transfer_link, transfer_link_expires_at
  )
  VALUES (
    v_escrow.escrow_id,
    v_escrow.buyer_id,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN v_link ELSE NULL END,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN p_transfer_link_expires_at ELSE NULL END
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET transfer_link = EXCLUDED.transfer_link,
      transfer_link_expires_at = EXCLUDED.transfer_link_expires_at;

  IF v_state = 'succeeded' THEN
    UPDATE public.payments
    SET payment_status = 'refunded'::public.payment_status_enum
    WHERE payment_id = v_escrow.payment_id
      AND payment_status = 'paid'::public.payment_status_enum;
  END IF;

  IF v_state IS DISTINCT FROM v_escrow.refund_state THEN
    SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
    PERFORM public._notify_refund_buyer(v_escrow, v_state);
  END IF;

  RETURN jsonb_build_object('success', true, 'refund_state', v_state::text);
END;
$$;

-- Clears a retry lock after the admin verified PayMongo has no live refund.
CREATE OR REPLACE FUNCTION public.clear_unverified_refund_lock(p_escrow_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public._is_service_role() AND NOT (auth.uid() IS NOT NULL AND public.is_admin()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  UPDATE public.escrow
  SET refund_lock_at = NULL,
      refund_provider_error = 'verified_no_live_refund',
      refund_last_checked_at = now()
  WHERE escrow_id = p_escrow_id
    AND status = 'refunded'::public.escrow_status_enum
    AND refund_state = 'manual_required'::public.escrow_refund_state_enum;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_refunds_to_reconcile(p_limit integer DEFAULT 25)
RETURNS TABLE (
  escrow_id uuid,
  paymongo_refund_id text,
  paymongo_payment_id text,
  paymongo_channel text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public._is_service_role() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT e.escrow_id, e.paymongo_refund_id, p.paymongo_payment_id::text, p.paymongo_channel
  FROM public.escrow e
  JOIN public.payments p ON p.payment_id = e.payment_id
  WHERE e.status = 'refunded'::public.escrow_status_enum
    AND e.refund_state IN (
      'provider_pending'::public.escrow_refund_state_enum,
      'awaiting_buyer_claim'::public.escrow_refund_state_enum
    )
    AND e.paymongo_refund_id IS NOT NULL
    AND (
      e.refund_last_checked_at IS NULL
      OR e.refund_last_checked_at < now() - interval '10 minutes'
    )
  ORDER BY e.refund_last_checked_at NULLS FIRST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 25), 100));
END;
$$;

-- ===========================================================================
-- 7. Manual GCash refund: buyer details + admin recording
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.submit_my_refund_gcash(
  p_escrow_id uuid,
  p_account_name text,
  p_mobile_number text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_escrow public.escrow%ROWTYPE;
  v_name text := btrim(coalesce(p_account_name, ''));
  v_mobile text := regexp_replace(coalesce(p_mobile_number, ''), '[^0-9+]', '', 'g');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF v_mobile LIKE '+63%' THEN
    v_mobile := '0' || substr(v_mobile, 4);
  ELSIF v_mobile LIKE '63%' AND char_length(v_mobile) = 12 THEN
    v_mobile := '0' || substr(v_mobile, 3);
  END IF;

  IF char_length(v_name) NOT BETWEEN 2 AND 80 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the name on your GCash account.');
  END IF;
  IF v_mobile !~ '^09[0-9]{9}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid GCash number, like 09171234567.');
  END IF;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = p_escrow_id FOR UPDATE;
  IF NOT FOUND OR v_escrow.buyer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Refund not found.');
  END IF;

  IF v_escrow.refund_state IS DISTINCT FROM 'manual_required'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'GCash details are only needed when the automatic refund could not be completed.'
    );
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, gcash_account_name, gcash_mobile_number, gcash_submitted_at
  )
  VALUES (v_escrow.escrow_id, v_uid, v_name, v_mobile, now())
  ON CONFLICT (escrow_id) DO UPDATE
  SET gcash_account_name = EXCLUDED.gcash_account_name,
      gcash_mobile_number = EXCLUDED.gcash_mobile_number,
      gcash_submitted_at = EXCLUDED.gcash_submitted_at;

  PERFORM public._notify_refund_admins(
    v_escrow,
    'Buyer added GCash for refund',
    'The buyer added GCash details for a ' || public._peso_text(v_escrow.amount_centavos) ||
      ' manual refund. Send it and record the transfer.'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_record_manual_refund(
  p_escrow_id uuid,
  p_amount_centavos integer,
  p_reference text,
  p_sent_at timestamptz,
  p_evidence_path text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_gcash_account_name text DEFAULT NULL,
  p_gcash_mobile_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_escrow public.escrow%ROWTYPE;
  v_details public.escrow_refund_details%ROWTYPE;
  v_reference text := btrim(coalesce(p_reference, ''));
  v_note text := NULLIF(btrim(coalesce(p_note, '')), '');
  v_name text;
  v_mobile text;
  v_evidence text := NULLIF(btrim(coalesce(p_evidence_path, '')), '');
  v_number text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can record a manual refund.');
  END IF;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = p_escrow_id FOR UPDATE;
  IF NOT FOUND OR v_escrow.status IS DISTINCT FROM 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Refund not found.');
  END IF;

  IF v_escrow.refund_state = 'manual_completed'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object('success', true, 'already_recorded', true);
  END IF;

  IF v_escrow.refund_state IS DISTINCT FROM 'manual_required'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This refund is still with PayMongo. Do not send GCash unless PayMongo has failed.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A PayMongo attempt has an unconfirmed result. Check PayMongo status before sending GCash.'
    );
  END IF;

  IF p_amount_centavos IS DISTINCT FROM v_escrow.amount_centavos THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The amount sent must equal the refund amount of ' ||
        public._peso_text(v_escrow.amount_centavos) || '.'
    );
  END IF;

  IF char_length(v_reference) NOT BETWEEN 4 AND 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash reference number.');
  END IF;

  IF p_sent_at IS NULL OR p_sent_at > now() + interval '1 hour'
     OR p_sent_at < v_escrow.refunded_at - interval '1 day' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the date the GCash transfer was sent.');
  END IF;

  IF v_evidence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Attach the GCash receipt for this refund.');
  END IF;

  IF v_evidence NOT LIKE 'refunds/' || v_escrow.buyer_id::text || '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'The receipt file is not linked to this refund.');
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 1,000 characters.');
  END IF;

  SELECT * INTO v_details FROM public.escrow_refund_details WHERE escrow_id = v_escrow.escrow_id;

  v_name := COALESCE(NULLIF(btrim(coalesce(p_gcash_account_name, '')), ''), v_details.gcash_account_name);
  v_mobile := COALESCE(
    NULLIF(regexp_replace(coalesce(p_gcash_mobile_number, ''), '[^0-9]', '', 'g'), ''),
    v_details.gcash_mobile_number
  );

  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 2 AND 80 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash account name the refund was sent to.');
  END IF;
  IF v_mobile IS NULL OR v_mobile !~ '^09[0-9]{9}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash number the refund was sent to.');
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, gcash_account_name, gcash_mobile_number,
    manual_amount_centavos, manual_reference, manual_sent_at,
    manual_evidence_path, manual_note, manual_recorded_by, manual_recorded_at
  )
  VALUES (
    v_escrow.escrow_id, v_escrow.buyer_id, v_name, v_mobile,
    p_amount_centavos, v_reference, p_sent_at,
    v_evidence, v_note, v_uid, now()
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET gcash_account_name = EXCLUDED.gcash_account_name,
      gcash_mobile_number = EXCLUDED.gcash_mobile_number,
      manual_amount_centavos = EXCLUDED.manual_amount_centavos,
      manual_reference = EXCLUDED.manual_reference,
      manual_sent_at = EXCLUDED.manual_sent_at,
      manual_evidence_path = EXCLUDED.manual_evidence_path,
      manual_note = EXCLUDED.manual_note,
      manual_recorded_by = EXCLUDED.manual_recorded_by,
      manual_recorded_at = EXCLUDED.manual_recorded_at,
      transfer_link = NULL,
      transfer_link_expires_at = NULL;

  UPDATE public.escrow
  SET refund_state = 'manual_completed',
      refund_completed_at = now(),
      refund_last_checked_at = now()
  WHERE escrow_id = v_escrow.escrow_id;

  UPDATE public.payments
  SET payment_status = 'refunded'::public.payment_status_enum
  WHERE payment_id = v_escrow.payment_id
    AND payment_status = 'paid'::public.payment_status_enum;

  SELECT COALESCE(o.order_number, '') INTO v_number
  FROM public.orders o WHERE o.order_id = v_escrow.order_id;

  INSERT INTO public.admin_audit_logs (
    category, event_type, status, summary, actor_user_id, target_type, target_id, details
  )
  VALUES (
    'payments_escrow',
    'manual_refund_recorded',
    'success',
    'Manual GCash refund of ' || public._peso_text(p_amount_centavos) ||
      ' recorded for Order #' || v_number,
    v_uid,
    'order',
    v_escrow.order_id::text,
    jsonb_build_object(
      'escrow_id', v_escrow.escrow_id,
      'amount_centavos', p_amount_centavos,
      'gcash_reference', v_reference,
      'sent_at', p_sent_at,
      'has_evidence', v_evidence IS NOT NULL
    )
  );

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
  PERFORM public._notify_refund_buyer(v_escrow, 'manual_completed');

  RETURN jsonb_build_object('success', true, 'refund_state', 'manual_completed');
END;
$$;

-- If the last PayMongo refund call had no confirmed result, PayMongo may still
-- have created the refund. Releasing the same money to the seller would pay
-- twice, so every release path is blocked until a later attempt settles it.
CREATE OR REPLACE FUNCTION public._guard_release_after_unconfirmed_refund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_last text;
BEGIN
  IF NEW.status = 'released'::public.escrow_status_enum
     AND OLD.status IS DISTINCT FROM 'released'::public.escrow_status_enum THEN
    SELECT a.outcome INTO v_last
    FROM public.escrow_refund_attempts a
    WHERE a.escrow_id = NEW.escrow_id
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF v_last = 'unknown' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'A PayMongo refund for this order has no confirmed result. '
          || 'Refund the buyer again so ThriftLine can check PayMongo before releasing.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._guard_release_after_unconfirmed_refund()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_escrow_guard_unconfirmed_refund ON public.escrow;
CREATE TRIGGER trg_escrow_guard_unconfirmed_refund
  BEFORE UPDATE OF status ON public.escrow
  FOR EACH ROW
  EXECUTE FUNCTION public._guard_release_after_unconfirmed_refund();

REVOKE ALL ON FUNCTION public.record_refund_attempt(
  uuid, text, text, text, text, integer, text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_refund_attempt(
  uuid, text, text, text, text, integer, text, text, boolean
) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.apply_refund_provider_update(text, text, text, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_refund_provider_update(text, text, text, timestamptz, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.prepare_refund_retry(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_refund_retry(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.apply_refund_retry_result(
  uuid, text, text, text, text, timestamptz, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_refund_retry_result(
  uuid, text, text, text, text, timestamptz, text
) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.clear_unverified_refund_lock(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_unverified_refund_lock(uuid)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.list_refunds_to_reconcile(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_refunds_to_reconcile(integer) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.submit_my_refund_gcash(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_my_refund_gcash(uuid, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_record_manual_refund(
  uuid, integer, text, timestamptz, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_record_manual_refund(
  uuid, integer, text, timestamptz, text, text, text, text
) TO authenticated;

-- ===========================================================================
-- 8. Buyer transaction history with refund state
-- ===========================================================================

DROP FUNCTION IF EXISTS public.list_my_payment_transactions();

CREATE OR REPLACE FUNCTION public.list_my_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  paid_at timestamptz,
  amount_centavos integer,
  payment_status text,
  payment_method text,
  paymongo_channel text,
  transaction_reference text,
  refunded_at timestamptz,
  refund_amount_centavos integer,
  refund_provider_status text,
  escrow_id uuid,
  refund_state text,
  refund_completed_at timestamptz,
  refund_transfer_link text,
  refund_transfer_link_expires_at timestamptz,
  refund_gcash_submitted boolean,
  manual_refund_reference text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.payment_id,
    o.order_id,
    o.order_number::text,
    COALESCE(
      (
        SELECT oi.title::text
        FROM public.order_items oi
        WHERE oi.order_id = o.order_id
        ORDER BY oi.created_at
        LIMIT 1
      ),
      'Order'::text
    ) AS product_title,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    p.payment_status::text,
    p.payment_method::text,
    p.paymongo_channel::text,
    p.transaction_reference::text,
    e.refunded_at,
    CASE
      WHEN e.status = 'refunded'::public.escrow_status_enum
        THEN COALESCE(e.amount_centavos, p.amount_centavos)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text,
    e.escrow_id,
    e.refund_state::text,
    e.refund_completed_at,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link
      ELSE NULL
    END AS refund_transfer_link,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link_expires_at
      ELSE NULL
    END AS refund_transfer_link_expires_at,
    (d.gcash_submitted_at IS NOT NULL) AS refund_gcash_submitted,
    d.manual_reference AS manual_refund_reference
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
  LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
  WHERE o.buyer_id = v_uid
    AND p.payment_status IN (
      'paid'::public.payment_status_enum,
      'refunded'::public.payment_status_enum
    )
  ORDER BY COALESCE(e.refunded_at, public.order_paid_at(o.order_id), p.updated_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_payment_transactions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_payment_transactions()
  TO authenticated, postgres, service_role;
