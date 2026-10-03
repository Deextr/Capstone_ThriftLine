-- Lock freelance rider edits once delivery is out for delivery or later.
-- Persist custom text when the seller records "other" delivery failure reasons.

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS delivery_failure_details text;

CREATE OR REPLACE FUNCTION public.assign_freelance_rider(
  p_order_id uuid,
  p_rider_name text,
  p_rider_phone text,
  p_vehicle_type text,
  p_plate_number text DEFAULT NULL,
  p_estimated_delivery_at timestamptz DEFAULT NULL,
  p_delivery_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_shipment_id uuid;
  v_phone text;
  v_name text;
  v_vehicle text;
  v_plate text;
  v_notes text;
  v_prev public.delivery_status_enum;
  v_assigned boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_name := NULLIF(btrim(COALESCE(p_rider_name, '')), '');
  v_vehicle := lower(NULLIF(btrim(COALESCE(p_vehicle_type, '')), ''));
  v_phone := public.normalize_ph_mobile(p_rider_phone);
  v_plate := NULLIF(btrim(COALESCE(p_plate_number, '')), '');
  v_notes := NULLIF(btrim(COALESCE(p_delivery_notes, '')), '');

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the rider name.');
  END IF;
  IF v_phone IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Enter a valid Philippine mobile number.'
    );
  END IF;
  IF v_vehicle IS NULL
     OR v_vehicle NOT IN ('motorcycle', 'car', 'van', 'bicycle', 'other') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a vehicle type.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.seller_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status IN (
       'pending'::public.order_status_enum,
       'cancelled'::public.order_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a paid order can be arranged for delivery.'
    );
  END IF;

  IF v_order.order_status IN (
       'completed'::public.order_status_enum,
       'disputed'::public.order_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order can no longer be arranged for delivery.'
    );
  END IF;

  IF NOT public.order_has_paid_payment(p_order_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a paid order can be arranged for delivery.'
    );
  END IF;

  v_shipment_id := public.ensure_paid_shipment(p_order_id);
  IF v_shipment_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a paid order can be arranged for delivery.'
    );
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE shipment_id = v_shipment_id
  FOR UPDATE;

  IF v_shipment.delivery_verified_at IS NOT NULL
     OR v_shipment.delivery_status IN (
          'out_for_delivery'::public.delivery_status_enum,
          'awaiting_delivery_verification'::public.delivery_status_enum,
          'delivery_verified'::public.delivery_status_enum,
          'inspection_period'::public.delivery_status_enum,
          'completed'::public.delivery_status_enum,
          'cancelled'::public.delivery_status_enum,
          'disputed'::public.delivery_status_enum,
          'delivery_failed'::public.delivery_status_enum
        ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Rider details are locked while delivery is in progress.'
    );
  END IF;

  v_prev := v_shipment.delivery_status;

  UPDATE public.shipments
  SET rider_name = v_name,
      rider_phone = v_phone,
      vehicle_type = v_vehicle,
      plate_number = v_plate,
      delivery_notes = v_notes,
      estimated_delivery_at = p_estimated_delivery_at,
      delivery_status = CASE
        WHEN delivery_status = 'seller_preparing'::public.delivery_status_enum
          THEN 'rider_assigned'::public.delivery_status_enum
        ELSE delivery_status
      END,
      rider_assigned_at = CASE
        WHEN delivery_status = 'seller_preparing'::public.delivery_status_enum
          THEN now()
        ELSE COALESCE(rider_assigned_at, now())
      END
  WHERE shipment_id = v_shipment_id
  RETURNING * INTO v_shipment;

  v_assigned := v_prev IS DISTINCT FROM v_shipment.delivery_status;

  IF v_assigned THEN
    PERFORM public.record_delivery_event(
      v_shipment.shipment_id,
      p_order_id,
      auth.uid(),
      'freelance_rider_assigned',
      v_prev,
      v_shipment.delivery_status,
      jsonb_build_object('vehicle_type', v_vehicle)
    );
    PERFORM public.notify_user(
      v_order.buyer_id,
      'shipped',
      'Freelance rider assigned',
      'A freelance rider has been assigned to Order #' ||
        COALESCE(v_order.order_number, '') || '.',
      jsonb_build_object('order_id', p_order_id)
    );
  ELSE
    PERFORM public.record_delivery_event(
      v_shipment.shipment_id,
      p_order_id,
      auth.uid(),
      'freelance_rider_updated',
      v_prev,
      v_shipment.delivery_status,
      jsonb_build_object('vehicle_type', v_vehicle)
    );
  END IF;

  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    v_shipment.delivery_status
  );

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', v_shipment.shipment_id,
    'delivery_status', v_shipment.delivery_status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_delivery_failed(
  p_order_id uuid,
  p_reason text,
  p_details text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_reason public.delivery_failure_reason_enum;
  v_details text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  BEGIN
    v_reason := btrim(COALESCE(p_reason, ''))::public.delivery_failure_reason_enum;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('success', false, 'error', 'Choose a valid reason.');
  END;

  v_details := NULLIF(btrim(COALESCE(p_details, '')), '');

  IF v_reason = 'other'::public.delivery_failure_reason_enum THEN
    IF v_details IS NULL OR length(v_details) < 10 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Please describe the delivery problem.'
      );
    END IF;
    IF length(v_details) > 1000 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Keep your description under 1,000 characters.'
      );
    END IF;
  ELSE
    v_details := NULL;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.seller_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF NOT public.order_has_paid_payment(p_order_id)
     OR v_order.order_status IN (
          'pending'::public.order_status_enum,
          'cancelled'::public.order_status_enum,
          'completed'::public.order_status_enum,
          'disputed'::public.order_status_enum
        ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This delivery cannot be marked failed.'
    );
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery is not ready.');
  END IF;

  IF v_shipment.delivery_status = 'delivery_failed'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_failed', true
    );
  END IF;

  IF v_shipment.delivery_status IS DISTINCT FROM
       'out_for_delivery'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Record a failed delivery only while the parcel is out for delivery.'
    );
  END IF;

  IF v_shipment.delivery_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A verified delivery cannot be marked failed.'
    );
  END IF;

  UPDATE public.shipments
  SET delivery_status = 'delivery_failed'::public.delivery_status_enum,
      delivery_failed_at = now(),
      delivery_failure_reason = v_reason,
      delivery_failure_details = v_details
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'delivery_failed',
    v_shipment.delivery_status,
    'delivery_failed'::public.delivery_status_enum,
    jsonb_build_object(
      'reason', v_reason::text,
      'details', v_details
    )
  );
  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    'delivery_failed'::public.delivery_status_enum
  );

  PERFORM public.notify_user(
    v_order.buyer_id,
    'system',
    'Delivery was not completed',
    'The seller recorded that delivery could not be completed for Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN jsonb_build_object('success', true, 'already_failed', false);
END;
$$;

DROP FUNCTION IF EXISTS public.mark_delivery_failed(uuid, text);

REVOKE ALL ON FUNCTION public.mark_delivery_failed(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_delivery_failed(uuid, text, text) TO authenticated;
