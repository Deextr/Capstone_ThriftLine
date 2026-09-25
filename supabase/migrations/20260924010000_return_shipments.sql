-- Optional physical return after an Admin refund on a delivery problem.
--
-- The refund itself stays in Phase 10. This table does not move money.
-- A return row is created only after the payment is already refunded.
-- The seller arranging a rider is not required for the buyer to stay refunded.
--
-- Do not edit earlier migrations. Idempotent.

-- ===========================================================================
-- 1. Enum
-- ===========================================================================

DO $$
BEGIN
  CREATE TYPE public.return_status_enum AS ENUM (
    'not_required',
    'waiting_for_rider',
    'rider_assigned',
    'picked_up',
    'returned',
    'cancelled_by_admin'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

-- ===========================================================================
-- 2. Table
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.return_shipments (
  return_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_id uuid NOT NULL UNIQUE
    REFERENCES public.delivery_disputes (dispute_id) ON DELETE RESTRICT,
  order_id uuid NOT NULL UNIQUE
    REFERENCES public.orders (order_id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  return_required boolean NOT NULL,
  seller_pays_return boolean NOT NULL DEFAULT false,
  status public.return_status_enum NOT NULL,
  rider_name text,
  rider_phone text,
  vehicle_type text,
  plate_number text,
  return_notes text,
  pickup_scheduled_at timestamptz,
  picked_up_at timestamptz,
  returned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT return_shipments_vehicle_type_chk CHECK (
    vehicle_type IS NULL
    OR vehicle_type IN ('motorcycle', 'car', 'van', 'bicycle', 'other')
  ),
  CONSTRAINT return_shipments_status_matches_requirement CHECK (
    (
      return_required = false
      AND status = 'not_required'::public.return_status_enum
    )
    OR (
      return_required = true
      AND status <> 'not_required'::public.return_status_enum
    )
  ),
  CONSTRAINT return_shipments_seller_pays_chk CHECK (
    seller_pays_return = return_required
  )
);

CREATE INDEX IF NOT EXISTS return_shipments_seller_status_idx
  ON public.return_shipments (seller_id, status);

CREATE INDEX IF NOT EXISTS return_shipments_buyer_status_idx
  ON public.return_shipments (buyer_id, status);

DROP TRIGGER IF EXISTS trg_return_shipments_updated_at ON public.return_shipments;
CREATE TRIGGER trg_return_shipments_updated_at
BEFORE UPDATE ON public.return_shipments
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.return_shipments IS
  'Physical return after a delivery-problem refund. Does not control the refund.';

-- ===========================================================================
-- 3. RLS
-- ===========================================================================

ALTER TABLE public.return_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_shipments FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS return_shipments_select_participant ON public.return_shipments;
CREATE POLICY return_shipments_select_participant ON public.return_shipments
  FOR SELECT TO authenticated
  USING (
    buyer_id = auth.uid()
    OR seller_id = auth.uid()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS return_shipments_write_postgres ON public.return_shipments;
CREATE POLICY return_shipments_write_postgres ON public.return_shipments
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.return_shipments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.return_shipments TO authenticated;
GRANT ALL ON TABLE public.return_shipments TO postgres, service_role;

-- ===========================================================================
-- 4. Admin records the return choice after the refund exists
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.record_refund_return(
  p_dispute_id uuid,
  p_return_required boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_existing public.return_shipments%ROWTYPE;
  v_status public.return_status_enum;
  v_return_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can decide whether this item must be returned.'
    );
  END IF;

  IF p_return_required IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Choose whether the item must be returned.'
    );
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

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.escrow e
    WHERE e.order_id = v_order.order_id
      AND e.status = 'refunded'::public.escrow_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Record the refund before deciding on a return.'
    );
  END IF;

  SELECT * INTO v_existing
  FROM public.return_shipments
  WHERE dispute_id = v_dispute.dispute_id
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_id', v_existing.return_id,
      'return_required', v_existing.return_required,
      'return_status', v_existing.status::text
    );
  END IF;

  v_status := CASE
    WHEN p_return_required THEN 'waiting_for_rider'::public.return_status_enum
    ELSE 'not_required'::public.return_status_enum
  END;

  INSERT INTO public.return_shipments (
    dispute_id,
    order_id,
    buyer_id,
    seller_id,
    return_required,
    seller_pays_return,
    status
  )
  VALUES (
    v_dispute.dispute_id,
    v_order.order_id,
    v_order.buyer_id,
    v_order.seller_id,
    p_return_required,
    p_return_required,
    v_status
  )
  RETURNING return_id INTO v_return_id;

  IF p_return_required THEN
    PERFORM public.notify_user(
      v_order.buyer_id,
      'orderConfirmed',
      'Refund approved',
      'Your refund has been approved. The seller is responsible for arranging the return delivery. Please prepare the item for pickup.',
      jsonb_build_object('order_id', v_order.order_id, 'return_required', true)
    );
    PERFORM public.notify_user(
      v_order.seller_id,
      'system',
      'Item return required',
      'The buyer was refunded for Order #' || COALESCE(v_order.order_number, '') ||
        '. Arrange a rider to pick the item up. This does not change the refund.',
      jsonb_build_object('order_id', v_order.order_id, 'return_required', true)
    );
  ELSE
    PERFORM public.notify_user(
      v_order.buyer_id,
      'orderConfirmed',
      'Refund approved',
      'Your refund has been approved. You do not need to return the item.',
      jsonb_build_object('order_id', v_order.order_id, 'return_required', false)
    );
    PERFORM public.notify_user(
      v_order.seller_id,
      'system',
      'Payment refunded',
      'The buyer was refunded for Order #' || COALESCE(v_order.order_number, '') ||
        '. No item return is required.',
      jsonb_build_object('order_id', v_order.order_id, 'return_required', false)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_id', v_return_id,
    'return_required', p_return_required,
    'return_status', v_status::text
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_return_shipment(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can stop this return.'
    );
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No return was found for this order.');
  END IF;

  IF v_row.status IN (
       'returned'::public.return_status_enum,
       'not_required'::public.return_status_enum,
       'cancelled_by_admin'::public.return_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_status', v_row.status::text
    );
  END IF;

  UPDATE public.return_shipments
  SET status = 'cancelled_by_admin'::public.return_status_enum
  WHERE return_id = v_row.return_id
    AND status IN (
      'waiting_for_rider'::public.return_status_enum,
      'rider_assigned'::public.return_status_enum,
      'picked_up'::public.return_status_enum
    );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'This return can no longer be stopped.');
  END IF;

  PERFORM public.notify_user(
    v_row.buyer_id,
    'system',
    'Return stopped',
    'An admin stopped the item return. Your refund is unchanged.',
    jsonb_build_object('order_id', v_row.order_id)
  );
  PERFORM public.notify_user(
    v_row.seller_id,
    'system',
    'Return stopped',
    'An admin stopped the item return. The buyer refund is unchanged.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_status', 'cancelled_by_admin'
  );
END;
$$;

-- ===========================================================================
-- 5. Seller arranges the rider. Buyer confirms handoff. Seller confirms return.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.arrange_return_rider(
  p_order_id uuid,
  p_rider_name text,
  p_rider_phone text,
  p_vehicle_type text,
  p_plate_number text DEFAULT NULL,
  p_pickup_scheduled_at timestamptz DEFAULT NULL,
  p_return_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
  v_name text;
  v_phone text;
  v_vehicle text;
  v_plate text;
  v_notes text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_name := NULLIF(btrim(COALESCE(p_rider_name, '')), '');
  v_phone := public.normalize_ph_mobile(p_rider_phone);
  v_vehicle := lower(NULLIF(btrim(COALESCE(p_vehicle_type, '')), ''));
  v_plate := NULLIF(btrim(COALESCE(p_plate_number, '')), '');
  v_notes := NULLIF(btrim(COALESCE(p_return_notes, '')), '');

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the rider name.');
  END IF;
  IF char_length(v_name) > 80 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the rider name shorter.');
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
  IF v_notes IS NOT NULL AND char_length(v_notes) > 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 500 characters.');
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_row.seller_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Return not found.');
  END IF;

  IF NOT v_row.return_required
     OR v_row.status NOT IN (
       'waiting_for_rider'::public.return_status_enum,
       'rider_assigned'::public.return_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A rider can no longer be assigned for this return.'
    );
  END IF;

  UPDATE public.return_shipments
  SET
    status = 'rider_assigned'::public.return_status_enum,
    rider_name = v_name,
    rider_phone = v_phone,
    vehicle_type = v_vehicle,
    plate_number = v_plate,
    return_notes = v_notes,
    pickup_scheduled_at = p_pickup_scheduled_at
  WHERE return_id = v_row.return_id
    AND status IN (
      'waiting_for_rider'::public.return_status_enum,
      'rider_assigned'::public.return_status_enum
    );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'A rider can no longer be assigned for this return.');
  END IF;

  PERFORM public.notify_user(
    v_row.buyer_id,
    'shipped',
    'Rider assigned',
    v_name || ' will pick up the item. Hand it over only when the rider arrives.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'return_status', 'rider_assigned'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_return_handed_off(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_row.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Return not found.');
  END IF;

  IF v_row.status = 'picked_up'::public.return_status_enum
     OR v_row.status = 'returned'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_status', v_row.status::text
    );
  END IF;

  IF v_row.status IS DISTINCT FROM 'rider_assigned'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Wait until a rider is assigned before handing over the item.'
    );
  END IF;

  UPDATE public.return_shipments
  SET
    status = 'picked_up'::public.return_status_enum,
    picked_up_at = now()
  WHERE return_id = v_row.return_id
    AND status = 'rider_assigned'::public.return_status_enum;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record the handoff.');
  END IF;

  PERFORM public.notify_user(
    v_row.seller_id,
    'system',
    'Item handed to rider',
    'The buyer handed the item to the rider. Confirm when you receive it.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_status', 'picked_up'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_return_received(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_row.seller_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Return not found.');
  END IF;

  IF v_row.status = 'returned'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_status', 'returned'
    );
  END IF;

  IF v_row.status IS DISTINCT FROM 'picked_up'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Confirm the return only after the buyer hands the item to the rider.'
    );
  END IF;

  UPDATE public.return_shipments
  SET
    status = 'returned'::public.return_status_enum,
    returned_at = now()
  WHERE return_id = v_row.return_id
    AND status = 'picked_up'::public.return_status_enum;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not confirm this return.');
  END IF;

  PERFORM public.notify_user(
    v_row.buyer_id,
    'orderConfirmed',
    'Return completed',
    'The seller confirmed that the item was returned. Your refund is unchanged.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_status', 'returned'
  );
END;
$$;

-- ===========================================================================
-- 6. Grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.record_refund_return(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_refund_return(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_return_shipment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_return_shipment(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.arrange_return_rider(uuid, text, text, text, text, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.arrange_return_rider(uuid, text, text, text, text, timestamptz, text) TO authenticated;

REVOKE ALL ON FUNCTION public.confirm_return_handed_off(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_return_handed_off(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.confirm_return_received(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_return_received(uuid) TO authenticated;
