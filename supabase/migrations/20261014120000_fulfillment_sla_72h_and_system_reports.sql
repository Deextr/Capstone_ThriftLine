-- Retarget fulfillment SLA auto-cancel from 120h to 72h, record one
-- system-generated confirmed report, count resolved reports in seller trust,
-- and expose buyer payment/refund history. Do not rewrite 20261013200000.

-- ---------------------------------------------------------------------------
-- 1. SLA event keys
-- ---------------------------------------------------------------------------

ALTER TABLE public.fulfillment_sla_events
  DROP CONSTRAINT IF EXISTS fulfillment_sla_events_key_chk;

ALTER TABLE public.fulfillment_sla_events
  ADD CONSTRAINT fulfillment_sla_events_key_chk CHECK (
    event_key IN (
      'nudge_24h',
      'nudge_48h',
      'delayed_72h',
      'auto_cancel_120h',
      'auto_cancel_72h'
    )
  );

-- ---------------------------------------------------------------------------
-- 2. System-generated confirmed reports
-- ---------------------------------------------------------------------------

ALTER TABLE public.reports
  ALTER COLUMN reporter_id DROP NOT NULL;

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_not_self;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_not_self CHECK (
    reporter_id IS NULL OR reporter_id <> reported_user_id
  );

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'user';

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS enforcement_reason text;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS enforcement_metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.reports
  DROP CONSTRAINT IF EXISTS reports_source_chk;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_source_chk CHECK (source IN ('user', 'system'));

CREATE UNIQUE INDEX IF NOT EXISTS reports_system_fulfillment_once_idx
  ON public.reports (order_id)
  WHERE source = 'system'
    AND category = 'seller_not_processing_order'
    AND order_id IS NOT NULL;

COMMENT ON COLUMN public.reports.source IS
  'user = submitted by a member; system = automated deadline confirmation.';

-- ---------------------------------------------------------------------------
-- 3. Trust CR counts resolved + action_taken
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.recalculate_seller_trust(p_seller_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
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

  IF v_government THEN
    v_email := v_email OR public.trust_seller_email_verified(p_seller_id);
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
    AND r.status IN (
      'action_taken'::public.report_status_enum,
      'resolved'::public.report_status_enum
    );

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
  'Recomputes seller trust. Confirmed Reports count resolved and action_taken rows.';

-- ---------------------------------------------------------------------------
-- 4. Record at most one fulfillment SLA violation
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_fulfillment_sla_violation(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_paid timestamptz;
  v_report_id uuid;
  v_details text;
  v_meta jsonb;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  v_paid := public.order_paid_at(p_order_id);
  v_details :=
    'System confirmed fulfillment violation: paid order #' ||
    COALESCE(v_order.order_number, '') ||
    ' was not processed before the 72-hour deadline.';
  v_meta := jsonb_build_object(
    'paid_at', v_paid,
    'deadline_hours', 72,
    'event_key', 'auto_cancel_72h',
    'enforcement_source', 'fulfillment_sla'
  );

  SELECT r.report_id
    INTO v_report_id
  FROM public.reports r
  WHERE r.order_id = p_order_id
    AND r.category = 'seller_not_processing_order'
    AND r.status IN (
      'resolved'::public.report_status_enum,
      'action_taken'::public.report_status_enum
    )
  ORDER BY r.resolved_at NULLS LAST, r.created_at
  LIMIT 1;

  IF v_report_id IS NOT NULL THEN
    PERFORM public.recalculate_seller_trust(v_order.seller_id);
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'report_id', v_report_id
    );
  END IF;

  SELECT r.report_id
    INTO v_report_id
  FROM public.reports r
  WHERE r.order_id = p_order_id
    AND r.category = 'seller_not_processing_order'
    AND r.status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    )
  ORDER BY r.created_at
  LIMIT 1;

  IF v_report_id IS NOT NULL THEN
    UPDATE public.reports
    SET
      status = 'resolved'::public.report_status_enum,
      resolved_at = COALESCE(resolved_at, now()),
      reviewed_by = NULL,
      admin_response = 'Confirmed automatically when the 72-hour processing deadline passed.',
      enforcement_reason = 'fulfillment_sla_72h',
      enforcement_metadata = v_meta,
      updated_at = now()
    WHERE report_id = v_report_id;
    PERFORM public.recalculate_seller_trust(v_order.seller_id);
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', false,
      'closed_buyer_report', true,
      'report_id', v_report_id
    );
  END IF;

  INSERT INTO public.reports (
    reporter_id,
    reported_user_id,
    order_id,
    category,
    details,
    status,
    reviewed_by,
    resolved_at,
    source,
    enforcement_reason,
    enforcement_metadata,
    evidence_attempt_count
  ) VALUES (
    NULL,
    v_order.seller_id,
    p_order_id,
    'seller_not_processing_order',
    v_details,
    'resolved'::public.report_status_enum,
    NULL,
    now(),
    'system',
    'fulfillment_sla_72h',
    v_meta,
    1
  )
  RETURNING report_id INTO v_report_id;

  IF v_report_id IS NULL THEN
    SELECT r.report_id
      INTO v_report_id
    FROM public.reports r
    WHERE r.order_id = p_order_id
      AND r.source = 'system'
      AND r.category = 'seller_not_processing_order'
    LIMIT 1;
  END IF;

  PERFORM public.recalculate_seller_trust(v_order.seller_id);

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'report_id', v_report_id
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT r.report_id
      INTO v_report_id
    FROM public.reports r
    WHERE r.order_id = p_order_id
      AND r.source = 'system'
      AND r.category = 'seller_not_processing_order'
    LIMIT 1;
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'report_id', v_report_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.record_fulfillment_sla_violation(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_fulfillment_sla_violation(uuid)
  TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 5. Nudges: 24h expectation, 48h seller reminder only
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.process_fulfillment_sla()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
  v_paid timestamptz;
  v_age interval;
  v_count integer := 0;
BEGIN
  FOR v_row IN
    SELECT o.order_id, o.order_number, o.buyer_id, o.seller_id
    FROM public.orders o
    WHERE o.order_status = 'paid'::public.order_status_enum
      AND public.order_is_stuck_preparing(o.order_id)
  LOOP
    v_paid := public.order_paid_at(v_row.order_id);
    IF v_paid IS NULL THEN
      CONTINUE;
    END IF;
    v_age := now() - v_paid;

    IF v_age >= interval '24 hours' THEN
      INSERT INTO public.fulfillment_sla_events (order_id, event_key)
      VALUES (v_row.order_id, 'nudge_24h')
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.notify_user(
          v_row.seller_id,
          'system',
          'Process this paid order',
          'Order #' || COALESCE(v_row.order_number, '') ||
            ' has been paid for 24 hours. Prepare it for shipment.',
          jsonb_build_object('order_id', v_row.order_id, 'event', 'fulfillment_nudge_24h'),
          'seller'::public.notification_audience_enum
        );
        v_count := v_count + 1;
      END IF;
    END IF;

    IF v_age >= interval '48 hours' THEN
      INSERT INTO public.fulfillment_sla_events (order_id, event_key)
      VALUES (v_row.order_id, 'nudge_48h')
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.notify_user(
          v_row.seller_id,
          'system',
          'Reminder: process this order',
          'Reminder: Your paid order has not been processed yet. Please prepare it for shipment before the cancellation deadline.',
          jsonb_build_object('order_id', v_row.order_id, 'event', 'fulfillment_nudge_48h'),
          'seller'::public.notification_audience_enum
        );
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.process_fulfillment_sla() IS
  'Sends the 24h seller expectation nudge and the one-time 48h reminder.';

-- ---------------------------------------------------------------------------
-- 6. 72h refund candidates + prepare/finalize
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_fulfillment_sla_refund_candidates()
RETURNS TABLE (order_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT o.order_id
  FROM public.orders o
  JOIN public.escrow e ON e.order_id = o.order_id
  WHERE o.order_status = 'paid'::public.order_status_enum
    AND public.order_is_stuck_preparing(o.order_id)
    AND public.order_paid_at(o.order_id) <= now() - interval '72 hours'
    AND e.status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = o.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.reports r
      WHERE r.order_id = o.order_id
        AND r.status IN (
          'under_review'::public.report_status_enum,
          'needs_more_evidence'::public.report_status_enum
        )
        AND r.category IS DISTINCT FROM 'seller_not_processing_order'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.fulfillment_sla_events ev
      WHERE ev.order_id = o.order_id
        AND ev.event_key IN ('auto_cancel_72h', 'auto_cancel_120h')
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
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
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
    refund_lock_at = COALESCE(refund_lock_at, now()),
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
    'paymongo_payment_id', v_payment.paymongo_payment_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_fulfillment_sla_refund(
  p_order_id uuid,
  p_provider text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL
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
  v_buyer_refund_body text;
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

  UPDATE public.escrow
  SET
    status = 'refunded'::public.escrow_status_enum,
    refunded_at = now(),
    refund_reason = COALESCE(refund_reason, 'fulfillment_sla'),
    refund_lock_at = NULL,
    refund_provider = v_provider::public.escrow_refund_provider_enum,
    paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    refund_provider_status = COALESCE(NULLIF(btrim(coalesce(p_provider_status, '')), ''), v_provider)
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record this refund.');
  END IF;

  UPDATE public.payments
  SET payment_status = 'refunded'::public.payment_status_enum
  WHERE payment_id = v_escrow.payment_id
    AND payment_status = 'paid'::public.payment_status_enum;

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

  IF v_provider = 'paymongo' THEN
    v_buyer_refund_body :=
      'A refund has been sent to your original payment method. It can take a short time to appear.';
  ELSE
    v_buyer_refund_body :=
      'ThriftLine recorded the refund. If the amount is not in your payment method yet, it is still being processed.';
  END IF;

  IF v_notify THEN
    PERFORM public.notify_user(
      v_order.buyer_id,
      'orderConfirmed',
      'Order cancelled',
      'Your order was cancelled because the seller did not process it before the deadline. ' ||
        v_buyer_refund_body,
      jsonb_build_object(
        'order_id', v_order.order_id,
        'event', 'fulfillment_auto_cancel',
        'refund_provider', v_provider
      ),
      'buyer'::public.notification_audience_enum
    );
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
    'amount_centavos', v_escrow.amount_centavos,
    'violation_report_id', v_violation ->> 'report_id'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_fulfillment_sla_refund_candidates()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prepare_fulfillment_sla_refund(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_fulfillment_sla_refund(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_fulfillment_sla_refund_candidates()
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_fulfillment_sla_refund(uuid)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_fulfillment_sla_refund(uuid, text, text, text)
  TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 7. Buyer transaction history (auth.uid only)
-- ---------------------------------------------------------------------------

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
  refund_provider_status text
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
      WHEN p.payment_status = 'refunded'::public.payment_status_enum
        THEN COALESCE(e.amount_centavos, p.amount_centavos)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
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

COMMENT ON FUNCTION public.list_my_payment_transactions() IS
  'Successful and refunded payments for the signed-in buyer only.';
