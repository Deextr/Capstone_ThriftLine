-- Fulfillment SLA: paid-clock helpers, 48h report gate, seller/buyer nudges,
-- delayed-order count, and service-role auto-refund RPCs (PayMongo via Edge).

-- ---------------------------------------------------------------------------
-- 1. Helpers (paid clock + stuck preparing)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.order_paid_at(p_order_id uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT min(p.updated_at)
  FROM public.payments p
  WHERE p.order_id = p_order_id
    AND p.payment_status = 'paid'::public.payment_status_enum;
$$;

COMMENT ON FUNCTION public.order_paid_at(uuid) IS
  'Earliest payments.updated_at where payment_status = paid.';

CREATE OR REPLACE FUNCTION public.order_is_stuck_preparing(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    LEFT JOIN public.shipments s ON s.order_id = o.order_id
    WHERE o.order_id = p_order_id
      AND o.order_status NOT IN (
        'pending'::public.order_status_enum,
        'cancelled'::public.order_status_enum,
        'completed'::public.order_status_enum,
        'disputed'::public.order_status_enum
      )
      AND EXISTS (
        SELECT 1
        FROM public.payments p
        WHERE p.order_id = o.order_id
          AND p.payment_status = 'paid'::public.payment_status_enum
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.payments p
        WHERE p.order_id = o.order_id
          AND p.payment_status = 'refunded'::public.payment_status_enum
      )
      AND (
        s.shipment_id IS NULL
        OR (
          s.delivery_status = 'seller_preparing'::public.delivery_status_enum
          AND s.rider_assigned_at IS NULL
          AND s.ready_for_pickup_at IS NULL
          AND s.picked_up_at IS NULL
        )
      )
  );
$$;

COMMENT ON FUNCTION public.order_is_stuck_preparing(uuid) IS
  'Paid order still in seller_preparing with no rider/handoff timestamps.';

REVOKE ALL ON FUNCTION public.order_paid_at(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.order_is_stuck_preparing(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.order_paid_at(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.order_is_stuck_preparing(uuid) TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 2. Idempotent SLA event log
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.fulfillment_sla_events (
  sla_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE CASCADE,
  event_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fulfillment_sla_events_key_chk CHECK (
    event_key IN ('nudge_24h', 'nudge_48h', 'delayed_72h', 'auto_cancel_120h')
  ),
  CONSTRAINT fulfillment_sla_events_order_key UNIQUE (order_id, event_key)
);

CREATE INDEX IF NOT EXISTS fulfillment_sla_events_order_idx
  ON public.fulfillment_sla_events (order_id);

ALTER TABLE public.fulfillment_sla_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fulfillment_sla_events FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fulfillment_sla_events_admin_select ON public.fulfillment_sla_events;
CREATE POLICY fulfillment_sla_events_admin_select ON public.fulfillment_sla_events
  FOR SELECT TO authenticated
  USING (public.is_admin());

REVOKE ALL ON TABLE public.fulfillment_sla_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.fulfillment_sla_events TO authenticated;
GRANT ALL ON TABLE public.fulfillment_sla_events TO postgres, service_role;

-- ---------------------------------------------------------------------------
-- 3. 48h gate on seller_not_processing_order
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
  v_paid_at timestamptz;
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

  IF v_category = 'seller_not_processing_order' AND v_order.buyer_id = v_uid THEN
    IF NOT public.order_is_stuck_preparing(p_order_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'This order is already moving. Use Track delivery if you need an update.'
      );
    END IF;
    v_paid_at := public.order_paid_at(p_order_id);
    IF v_paid_at IS NULL OR v_paid_at > now() - interval '48 hours' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'You can report a shipping delay 48 hours after payment if the seller has not updated this order.'
      );
    END IF;
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
-- 4. Nudges (24h / 48h / 72h)
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
          'Ship this order',
          'Order #' || COALESCE(v_row.order_number, '') ||
            ' has been paid for 24 hours. Update the status or arrange delivery today.',
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
          'Buyer can report a delay',
          'Order #' || COALESCE(v_row.order_number, '') ||
            ' is still preparing after 48 hours. Ship or update it now.',
          jsonb_build_object('order_id', v_row.order_id, 'event', 'fulfillment_nudge_48h'),
          'seller'::public.notification_audience_enum
        );
        PERFORM public.notify_user(
          v_row.buyer_id,
          'orderConfirmed',
          'Your order is delayed',
          'The seller has not updated Order #' || COALESCE(v_row.order_number, '') ||
            '. You can report a problem from My Purchases.',
          jsonb_build_object('order_id', v_row.order_id, 'event', 'fulfillment_nudge_48h'),
          'buyer'::public.notification_audience_enum
        );
        v_count := v_count + 1;
      END IF;
    END IF;

    IF v_age >= interval '72 hours' THEN
      INSERT INTO public.fulfillment_sla_events (order_id, event_key)
      VALUES (v_row.order_id, 'delayed_72h')
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.notify_user(
          v_row.seller_id,
          'system',
          'Order flagged as delayed',
          'Order #' || COALESCE(v_row.order_number, '') ||
            ' has been paid for 72 hours without a shipping update. ThriftLine may cancel it soon.',
          jsonb_build_object('order_id', v_row.order_id, 'event', 'fulfillment_delayed_72h'),
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
  'Sends 24/48/72h fulfillment nudges once per stuck-preparing order.';

REVOKE ALL ON FUNCTION public.process_fulfillment_sla() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_fulfillment_sla() TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.fulfillment_overdue_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN (
    SELECT count(*)::integer
    FROM public.orders o
    WHERE public.order_is_stuck_preparing(o.order_id)
      AND public.order_paid_at(o.order_id) <= now() - interval '72 hours'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fulfillment_overdue_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fulfillment_overdue_count() TO authenticated, postgres, service_role;

-- ---------------------------------------------------------------------------
-- 5. Auto-cancel candidates + PayMongo refund RPCs (service_role)
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
    AND public.order_paid_at(o.order_id) <= now() - interval '120 hours'
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
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.fulfillment_sla_events ev
      WHERE ev.order_id = o.order_id
        AND ev.event_key = 'auto_cancel_120h'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.list_fulfillment_sla_refund_candidates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_fulfillment_sla_refund_candidates() TO postgres, service_role;

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

  IF public.order_paid_at(p_order_id) > now() - interval '120 hours' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Auto-cancel is not due yet.');
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

CREATE OR REPLACE FUNCTION public.abort_fulfillment_sla_refund(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed.');
  END IF;

  UPDATE public.escrow
  SET refund_lock_at = NULL
  WHERE order_id = p_order_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
    AND refunded_at IS NULL
    AND paymongo_refund_id IS NULL;

  RETURN jsonb_build_object('success', true);
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
    VALUES (p_order_id, 'auto_cancel_120h')
    ON CONFLICT DO NOTHING;
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
  VALUES (p_order_id, 'auto_cancel_120h')
  ON CONFLICT DO NOTHING;

  PERFORM public.notify_user(
    v_order.buyer_id,
    'orderConfirmed',
    'Order cancelled and refunded',
    'The seller did not prepare Order #' || COALESCE(v_order.order_number, '') ||
      ' in time. Your payment is being returned.',
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
    'Order auto-cancelled',
    'Order #' || COALESCE(v_order.order_number, '') ||
      ' was cancelled because it was not prepared or shipped in time. The buyer was refunded.',
    jsonb_build_object('order_id', v_order.order_id, 'event', 'fulfillment_auto_cancel'),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'refund',
    'status', 'refunded',
    'refund_provider', v_provider,
    'amount_centavos', v_escrow.amount_centavos
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_fulfillment_sla_refund(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.abort_fulfillment_sla_refund(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_fulfillment_sla_refund(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_fulfillment_sla_refund(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.abort_fulfillment_sla_refund(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_fulfillment_sla_refund(uuid, text, text, text) TO postgres, service_role;
