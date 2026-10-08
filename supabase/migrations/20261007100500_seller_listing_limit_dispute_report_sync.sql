-- Enforce max 10 active product listings per seller (concurrency-safe).
-- When an admin dismisses an order-linked community report, close the delivery
-- dispute hold and resume order/escrow (same outcome as close_delivery_dispute).
-- Fix inspection auto-complete skipping orders left in order_status = disputed.

-- ===========================================================================
-- 1. Seller active listing limit (products.status = active)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.seller_max_active_listings()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 10;
$$;

CREATE OR REPLACE FUNCTION public.seller_active_listing_count(
  p_seller_id uuid,
  p_exclude_product_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COUNT(*)::integer
  FROM public.products p
  WHERE p.seller_id = p_seller_id
    AND p.status = 'active'::public.product_status_enum
    AND (p_exclude_product_id IS NULL OR p.product_id <> p_exclude_product_id);
$$;

CREATE OR REPLACE FUNCTION public.assert_seller_active_listing_capacity(
  p_seller_id uuid,
  p_product_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_max integer;
  v_count integer;
BEGIN
  IF p_seller_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext('seller-active-listings:' || p_seller_id::text)
  );

  v_max := public.seller_max_active_listings();
  v_count := public.seller_active_listing_count(p_seller_id, p_product_id);

  IF v_count >= v_max THEN
    RAISE EXCEPTION
      'listing_limit_reached: You can have up to % active listings at a time. Mark an existing listing as inactive, sell an item, or remove a listing before posting another.',
      v_max
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_products_enforce_active_listing_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.seller_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'active'::public.product_status_enum
     AND (
       TG_OP = 'INSERT'
       OR OLD.status IS DISTINCT FROM 'active'::public.product_status_enum
     )
  THEN
    PERFORM public.assert_seller_active_listing_capacity(
      NEW.seller_id,
      NEW.product_id
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_enforce_active_listing_limit ON public.products;
CREATE TRIGGER trg_products_enforce_active_listing_limit
BEFORE INSERT OR UPDATE OF status, seller_id ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.trg_products_enforce_active_listing_limit();

CREATE OR REPLACE FUNCTION public.seller_listing_limit_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_max integer;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_max := public.seller_max_active_listings();
  v_count := public.seller_active_listing_count(v_uid, NULL);

  RETURN jsonb_build_object(
    'success', true,
    'max_active', v_max,
    'active_count', v_count,
    'can_publish', v_count < v_max
  );
END;
$$;

COMMENT ON FUNCTION public.seller_listing_limit_status() IS
  'Returns how many active listings the signed-in seller has versus the published cap.';

REVOKE ALL ON FUNCTION public.seller_active_listing_count(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.assert_seller_active_listing_capacity(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seller_listing_limit_status() TO authenticated;

-- ===========================================================================
-- 2. Dismissed order report → close delivery hold + resume lifecycle
-- ===========================================================================

CREATE OR REPLACE FUNCTION public._admin_finalize_dismissed_order_report(
  p_order_id uuid,
  p_admin_id uuid,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_note text;
  v_dispute_id uuid;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  v_note := nullif(left(trim(coalesce(p_note, '')), ''), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    v_note := left(v_note, 2000);
  END IF;

  SELECT d.dispute_id INTO v_dispute_id
  FROM public.delivery_disputes d
  WHERE d.order_id = p_order_id
    AND d.status = 'open'::public.delivery_dispute_status_enum
  FOR UPDATE;

  IF v_dispute_id IS NOT NULL THEN
    UPDATE public.delivery_disputes
    SET
      status = 'resolved'::public.delivery_dispute_status_enum,
      admin_note = COALESCE(admin_note, v_note),
      reviewed_by = COALESCE(reviewed_by, p_admin_id),
      resolved_at = COALESCE(resolved_at, now())
    WHERE dispute_id = v_dispute_id
      AND status = 'open'::public.delivery_dispute_status_enum;
  END IF;

  PERFORM public.resume_order_after_dispute_closed(p_order_id);
  PERFORM public.resume_escrow_after_dispute_closed(p_order_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_report(
  p_report_id uuid,
  p_decision text,
  p_admin_response text
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can review reports.'
    );
  END IF;

  IF p_report_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  v_decision := lower(trim(coalesce(p_decision, '')));
  IF v_decision NOT IN ('action_taken', 'resolved', 'dismissed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a valid decision.');
  END IF;

  v_response := trim(coalesce(p_admin_response, ''));
  IF char_length(v_response) < 8 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Write a short response for the reporter.'
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

  IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
    IF v_report.status::text = v_decision THEN
      IF v_decision = 'dismissed' AND v_report.order_id IS NOT NULL THEN
        PERFORM public._admin_finalize_dismissed_order_report(
          v_report.order_id,
          v_uid,
          v_response
        );
      END IF;
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

  UPDATE public.reports
  SET
    status = v_decision::public.report_status_enum,
    admin_response = v_response,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE report_id = p_report_id
    AND status = 'under_review'::public.report_status_enum;

  IF NOT FOUND THEN
    SELECT * INTO v_report
    FROM public.reports
    WHERE report_id = p_report_id;

    IF FOUND AND v_report.status::text = v_decision THEN
      IF v_decision = 'dismissed' AND v_report.order_id IS NOT NULL THEN
        PERFORM public._admin_finalize_dismissed_order_report(
          v_report.order_id,
          v_uid,
          v_response
        );
      END IF;
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

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id;

  IF v_decision = 'dismissed' AND v_report.order_id IS NOT NULL THEN
    PERFORM public._admin_finalize_dismissed_order_report(
      v_report.order_id,
      v_uid,
      v_response
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'report_id', p_report_id,
    'status', v_decision
  );
END;
$$;

COMMENT ON FUNCTION public.decide_report(uuid, text, text) IS
  'Admin-only. Moves a community report out of under_review. Dismissing an order-linked report also closes the delivery dispute hold and resumes order/escrow when eligible. Does not refund the buyer or release funds on action_taken.';

REVOKE ALL ON FUNCTION public._admin_finalize_dismissed_order_report(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_finalize_dismissed_order_report(uuid, uuid, text)
  TO postgres, service_role;

-- ===========================================================================
-- 3. Inspection auto-complete: do not skip stale order_status = disputed
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.complete_expired_inspections()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
  v_order public.orders%ROWTYPE;
  v_count integer := 0;
  v_open boolean;
BEGIN
  FOR v_row IN
    SELECT s.shipment_id, s.order_id, s.delivery_status
    FROM public.shipments s
    WHERE s.delivery_status = 'inspection_period'::public.delivery_status_enum
      AND s.delivery_verified_at IS NOT NULL
      AND s.inspection_expires_at IS NOT NULL
      AND s.inspection_expires_at <= now()
    FOR UPDATE OF s SKIP LOCKED
  LOOP
    SELECT * INTO v_order
    FROM public.orders
    WHERE order_id = v_row.order_id
    FOR UPDATE;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    IF v_order.order_status IN (
         'completed'::public.order_status_enum,
         'cancelled'::public.order_status_enum
       ) THEN
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = v_row.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    ) INTO v_open;

    IF v_open THEN
      CONTINUE;
    END IF;

    IF v_order.order_status = 'disputed'::public.order_status_enum
       AND v_row.delivery_status = 'inspection_period'::public.delivery_status_enum
    THEN
      PERFORM public.sync_order_status_for_delivery(
        v_row.order_id,
        'inspection_period'::public.delivery_status_enum
      );
      SELECT * INTO v_order
      FROM public.orders
      WHERE order_id = v_row.order_id;
    END IF;

    UPDATE public.shipments
    SET delivery_status = 'completed'::public.delivery_status_enum,
        auto_completed = true,
        completion_reason = COALESCE(
          completion_reason,
          'delivery_verified_no_dispute'
        ),
        completed_at = COALESCE(completed_at, now())
    WHERE shipment_id = v_row.shipment_id
      AND delivery_status = 'inspection_period'::public.delivery_status_enum;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    PERFORM public.record_delivery_event(
      v_row.shipment_id,
      v_row.order_id,
      NULL,
      'order_auto_completed',
      'inspection_period'::public.delivery_status_enum,
      'completed'::public.delivery_status_enum,
      jsonb_build_object('reason', 'delivery_verified_no_dispute')
    );
    PERFORM public.sync_order_status_for_delivery(
      v_row.order_id,
      'completed'::public.delivery_status_enum
    );

    PERFORM public.notify_user(
      v_order.buyer_id,
      'orderConfirmed',
      'Order completed',
      'Your order has been completed. Order #' ||
        COALESCE(v_order.order_number, '') || '.',
      jsonb_build_object('order_id', v_row.order_id)
    );
    PERFORM public.notify_user(
      v_order.seller_id,
      'system',
      'Order completed',
      'Order #' || COALESCE(v_order.order_number, '') ||
        ' was completed after the inspection period.',
      jsonb_build_object('order_id', v_row.order_id)
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Repair: dismissed/closed disputes with shipment or escrow still held as disputed.
DO $$
DECLARE
  v_row record;
BEGIN
  FOR v_row IN
    SELECT DISTINCT s.order_id
    FROM public.shipments s
    WHERE s.delivery_status = 'disputed'::public.delivery_status_enum
      AND s.delivery_verified_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.delivery_disputes d
        WHERE d.order_id = s.order_id
          AND d.status = 'open'::public.delivery_dispute_status_enum
      )
  LOOP
    PERFORM public.resume_order_after_dispute_closed(v_row.order_id);
    PERFORM public.resume_escrow_after_dispute_closed(v_row.order_id);
  END LOOP;

  FOR v_row IN
    SELECT e.order_id
    FROM public.escrow e
    WHERE e.status = 'disputed'::public.escrow_status_enum
      AND e.refund_lock_at IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.delivery_disputes d
        WHERE d.order_id = e.order_id
          AND d.status = 'open'::public.delivery_dispute_status_enum
      )
  LOOP
    PERFORM public.resume_escrow_after_dispute_closed(v_row.order_id);
  END LOOP;
END;
$$;
