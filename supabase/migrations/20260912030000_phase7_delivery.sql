-- Phase 7 — Freelance / local rider delivery monitoring and verification.
--
-- Does NOT create couriers, tracking URLs, rider accounts, escrow, or payouts.
-- Does NOT rewrite checkout, PayMongo, or stock.
-- Does NOT use the legacy courier `shipping` table or orders.courier /
-- orders.tracking_number (those columns stay for compatibility only).
--
-- Paid orders get a shipments row (trigger + backfill). Clients SELECT
-- participant delivery data. All writes go through SECURITY DEFINER RPCs.
--
-- Idempotent. Safe to re-run after a failed attempt.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ===========================================================================
-- 1. Enums
-- ===========================================================================

DO $$
BEGIN
  CREATE TYPE public.delivery_status_enum AS ENUM (
    'seller_preparing',
    'rider_assigned',
    'ready_for_pickup',
    'picked_up',
    'out_for_delivery',
    'awaiting_delivery_verification',
    'delivery_verified',
    'inspection_period',
    'delivery_failed',
    'disputed',
    'completed',
    'cancelled'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.delivery_method_enum AS ENUM ('freelance_rider');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.delivery_failure_reason_enum AS ENUM (
    'buyer_unavailable',
    'buyer_refused_delivery',
    'buyer_refused_verification',
    'unable_to_contact_buyer',
    'incorrect_address',
    'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.delivery_dispute_reason_enum AS ENUM (
    'parcel_not_received',
    'wrong_item',
    'damaged_item',
    'significantly_different',
    'missing_item',
    'missing_quantity',
    'empty_parcel',
    'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.delivery_dispute_status_enum AS ENUM (
    'open',
    'resolved'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ===========================================================================
-- 2. Tables
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.shipments (
  shipment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE CASCADE,
  delivery_method public.delivery_method_enum NOT NULL
    DEFAULT 'freelance_rider'::public.delivery_method_enum,
  rider_name text,
  rider_phone text,
  vehicle_type text,
  plate_number text,
  delivery_notes text,
  delivery_status public.delivery_status_enum NOT NULL
    DEFAULT 'seller_preparing'::public.delivery_status_enum,
  estimated_delivery_at timestamptz,
  rider_assigned_at timestamptz,
  ready_for_pickup_at timestamptz,
  picked_up_at timestamptz,
  out_for_delivery_at timestamptz,
  delivery_pin_hash text,
  delivery_pin_expires_at timestamptz,
  delivery_pin_attempts integer NOT NULL DEFAULT 0,
  delivery_pin_locked_until timestamptz,
  delivery_pin_used_at timestamptz,
  delivery_verified_at timestamptz,
  delivery_verification_method text,
  buyer_confirmed_received boolean NOT NULL DEFAULT false,
  buyer_confirmed_received_at timestamptz,
  inspection_started_at timestamptz,
  inspection_expires_at timestamptz,
  delivery_failed_at timestamptz,
  delivery_failure_reason public.delivery_failure_reason_enum,
  auto_completed boolean NOT NULL DEFAULT false,
  completion_reason text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT shipments_order_id_key UNIQUE (order_id),
  CONSTRAINT shipments_vehicle_type_chk CHECK (
    vehicle_type IS NULL
    OR vehicle_type IN ('motorcycle', 'car', 'van', 'bicycle', 'other')
  ),
  CONSTRAINT shipments_pin_attempts_chk CHECK (delivery_pin_attempts >= 0)
);

CREATE TABLE IF NOT EXISTS public.delivery_pin_secrets (
  shipment_id uuid PRIMARY KEY
    REFERENCES public.shipments (shipment_id) ON DELETE CASCADE,
  pin_code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.delivery_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL
    REFERENCES public.shipments (shipment_id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  event_type text NOT NULL,
  previous_status public.delivery_status_enum,
  new_status public.delivery_status_enum,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.delivery_disputes (
  dispute_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL
    REFERENCES public.shipments (shipment_id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders (order_id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  reason public.delivery_dispute_reason_enum NOT NULL,
  details text,
  status public.delivery_dispute_status_enum NOT NULL
    DEFAULT 'open'::public.delivery_dispute_status_enum,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS shipments_status_idx
  ON public.shipments (delivery_status);

CREATE INDEX IF NOT EXISTS shipments_inspection_expires_idx
  ON public.shipments (inspection_expires_at)
  WHERE delivery_status = 'inspection_period'::public.delivery_status_enum;

CREATE INDEX IF NOT EXISTS delivery_events_shipment_created_idx
  ON public.delivery_events (shipment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS delivery_disputes_order_idx
  ON public.delivery_disputes (order_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS delivery_disputes_open_order_uidx
  ON public.delivery_disputes (order_id)
  WHERE status = 'open'::public.delivery_dispute_status_enum;

DROP TRIGGER IF EXISTS trg_shipments_updated_at ON public.shipments;
CREATE TRIGGER trg_shipments_updated_at
  BEFORE UPDATE ON public.shipments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_delivery_disputes_updated_at ON public.delivery_disputes;
CREATE TRIGGER trg_delivery_disputes_updated_at
  BEFORE UPDATE ON public.delivery_disputes
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- 3. RLS — clients SELECT participant rows; no client writes
-- ===========================================================================

ALTER TABLE public.shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_pin_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_pin_secrets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_disputes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shipments_select_participant ON public.shipments;
CREATE POLICY shipments_select_participant ON public.shipments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = shipments.order_id
        AND (
          o.buyer_id = auth.uid()
          OR o.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

DROP POLICY IF EXISTS shipments_write_postgres ON public.shipments;
CREATE POLICY shipments_write_postgres ON public.shipments
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS delivery_events_select_participant ON public.delivery_events;
CREATE POLICY delivery_events_select_participant ON public.delivery_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = delivery_events.order_id
        AND (
          o.buyer_id = auth.uid()
          OR o.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

DROP POLICY IF EXISTS delivery_events_write_postgres ON public.delivery_events;
CREATE POLICY delivery_events_write_postgres ON public.delivery_events
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS delivery_disputes_select_participant ON public.delivery_disputes;
CREATE POLICY delivery_disputes_select_participant ON public.delivery_disputes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = delivery_disputes.order_id
        AND (
          o.buyer_id = auth.uid()
          OR o.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

DROP POLICY IF EXISTS delivery_disputes_write_postgres ON public.delivery_disputes;
CREATE POLICY delivery_disputes_write_postgres ON public.delivery_disputes
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS delivery_pin_secrets_write_postgres
  ON public.delivery_pin_secrets;
CREATE POLICY delivery_pin_secrets_write_postgres
  ON public.delivery_pin_secrets
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.shipments FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  shipment_id,
  order_id,
  delivery_method,
  rider_name,
  rider_phone,
  vehicle_type,
  plate_number,
  delivery_notes,
  delivery_status,
  estimated_delivery_at,
  rider_assigned_at,
  ready_for_pickup_at,
  picked_up_at,
  out_for_delivery_at,
  delivery_pin_expires_at,
  delivery_pin_attempts,
  delivery_pin_locked_until,
  delivery_pin_used_at,
  delivery_verified_at,
  delivery_verification_method,
  buyer_confirmed_received,
  buyer_confirmed_received_at,
  inspection_started_at,
  inspection_expires_at,
  delivery_failed_at,
  delivery_failure_reason,
  auto_completed,
  completion_reason,
  completed_at,
  created_at,
  updated_at
) ON public.shipments TO authenticated;
GRANT ALL ON TABLE public.shipments TO postgres, service_role;

REVOKE ALL ON TABLE public.delivery_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.delivery_events TO authenticated;
GRANT ALL ON TABLE public.delivery_events TO postgres, service_role;

REVOKE ALL ON TABLE public.delivery_disputes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.delivery_disputes TO authenticated;
GRANT ALL ON TABLE public.delivery_disputes TO postgres, service_role;

REVOKE ALL ON TABLE public.delivery_pin_secrets FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.delivery_pin_secrets TO postgres, service_role;

-- ===========================================================================
-- 4. Helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.inspection_period_hours()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 24;
$$;

CREATE OR REPLACE FUNCTION public.normalize_ph_mobile(p_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits text;
BEGIN
  IF p_phone IS NULL THEN
    RETURN NULL;
  END IF;
  v_digits := regexp_replace(p_phone, '[^0-9+]', '', 'g');
  IF v_digits LIKE '+%' THEN
    v_digits := substr(v_digits, 2);
  END IF;
  IF v_digits ~ '^63[0-9]{10}$' THEN
    RETURN '0' || substr(v_digits, 3);
  END IF;
  IF v_digits ~ '^9[0-9]{9}$' THEN
    RETURN '0' || v_digits;
  END IF;
  IF v_digits ~ '^09[0-9]{9}$' THEN
    RETURN v_digits;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.order_has_paid_payment(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.order_id = p_order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
  );
$$;

CREATE OR REPLACE FUNCTION public.touch_order_for_realtime(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.orders
  SET updated_at = now()
  WHERE order_id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_delivery_event(
  p_shipment_id uuid,
  p_order_id uuid,
  p_actor_user_id uuid,
  p_event_type text,
  p_previous public.delivery_status_enum,
  p_new public.delivery_status_enum,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.delivery_events (
    shipment_id,
    order_id,
    actor_user_id,
    event_type,
    previous_status,
    new_status,
    metadata
  )
  VALUES (
    p_shipment_id,
    p_order_id,
    p_actor_user_id,
    p_event_type,
    p_previous,
    p_new,
    COALESCE(p_metadata, '{}'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_order_status_for_delivery(
  p_order_id uuid,
  p_delivery_status public.delivery_status_enum
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_next public.order_status_enum;
BEGIN
  v_next := CASE p_delivery_status
    WHEN 'seller_preparing'::public.delivery_status_enum THEN 'paid'::public.order_status_enum
    WHEN 'rider_assigned'::public.delivery_status_enum THEN 'paid'::public.order_status_enum
    WHEN 'ready_for_pickup'::public.delivery_status_enum THEN 'paid'::public.order_status_enum
    WHEN 'picked_up'::public.delivery_status_enum THEN 'shipped'::public.order_status_enum
    WHEN 'out_for_delivery'::public.delivery_status_enum THEN 'shipped'::public.order_status_enum
    WHEN 'awaiting_delivery_verification'::public.delivery_status_enum THEN 'shipped'::public.order_status_enum
    WHEN 'delivery_verified'::public.delivery_status_enum THEN 'delivered'::public.order_status_enum
    WHEN 'inspection_period'::public.delivery_status_enum THEN 'delivered'::public.order_status_enum
    WHEN 'delivery_failed'::public.delivery_status_enum THEN 'shipped'::public.order_status_enum
    WHEN 'disputed'::public.delivery_status_enum THEN 'disputed'::public.order_status_enum
    WHEN 'completed'::public.delivery_status_enum THEN 'completed'::public.order_status_enum
    WHEN 'cancelled'::public.delivery_status_enum THEN 'cancelled'::public.order_status_enum
    ELSE NULL
  END;

  IF v_next IS NULL THEN
    PERFORM public.touch_order_for_realtime(p_order_id);
    RETURN;
  END IF;

  UPDATE public.orders
  SET order_status = v_next,
      updated_at = now()
  WHERE order_id = p_order_id
    AND order_status IS DISTINCT FROM v_next;

  IF NOT FOUND THEN
    PERFORM public.touch_order_for_realtime(p_order_id);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_delivery_pin(p_shipment_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_n bigint;
  v_pin text;
BEGIN
  v_n := ('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint;
  v_pin := lpad((v_n % 1000000)::text, 6, '0');

  UPDATE public.shipments
  SET delivery_pin_hash = crypt(v_pin, gen_salt('bf')),
      delivery_pin_expires_at = now() + interval '7 days',
      delivery_pin_attempts = 0,
      delivery_pin_locked_until = NULL,
      delivery_pin_used_at = NULL
  WHERE shipment_id = p_shipment_id;

  INSERT INTO public.delivery_pin_secrets (shipment_id, pin_code)
  VALUES (p_shipment_id, v_pin)
  ON CONFLICT (shipment_id) DO UPDATE
    SET pin_code = EXCLUDED.pin_code,
        created_at = now();

  RETURN v_pin;
END;
$$;

-- ===========================================================================
-- 5. ensure_paid_shipment + paid-order trigger (does not rewrite PayMongo)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_paid_shipment(p_order_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment_id uuid;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_order.order_status IN (
       'pending'::public.order_status_enum,
       'cancelled'::public.order_status_enum
     ) THEN
    RETURN NULL;
  END IF;

  IF v_order.order_status NOT IN (
       'paid'::public.order_status_enum,
       'shipped'::public.order_status_enum,
       'delivered'::public.order_status_enum,
       'completed'::public.order_status_enum,
       'disputed'::public.order_status_enum
     ) THEN
    RETURN NULL;
  END IF;

  SELECT s.shipment_id INTO v_shipment_id
  FROM public.shipments s
  WHERE s.order_id = p_order_id;

  IF v_shipment_id IS NOT NULL THEN
    RETURN v_shipment_id;
  END IF;

  IF NOT public.order_has_paid_payment(p_order_id) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.shipments (order_id, delivery_status)
  VALUES (
    p_order_id,
    'seller_preparing'::public.delivery_status_enum
  )
  ON CONFLICT (order_id) DO NOTHING
  RETURNING shipment_id INTO v_shipment_id;

  IF v_shipment_id IS NULL THEN
    SELECT s.shipment_id INTO v_shipment_id
    FROM public.shipments s
    WHERE s.order_id = p_order_id;
    RETURN v_shipment_id;
  END IF;

  PERFORM public.record_delivery_event(
    v_shipment_id,
    p_order_id,
    NULL,
    'delivery_created',
    NULL,
    'seller_preparing'::public.delivery_status_enum,
    '{}'::jsonb
  );

  PERFORM public.notify_user(
    v_order.buyer_id,
    'orderConfirmed',
    'Seller is preparing your order',
    'Your seller is preparing Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );
  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Paid order ready to prepare',
    'Your paid order is ready for preparation. Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN v_shipment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_orders_paid_ensure_shipment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.order_status = 'paid'::public.order_status_enum
     AND OLD.order_status IS DISTINCT FROM 'paid'::public.order_status_enum THEN
    BEGIN
      PERFORM public.ensure_paid_shipment(NEW.order_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'ensure_paid_shipment failed for %: %',
          NEW.order_id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_paid_ensure_shipment ON public.orders;
CREATE TRIGGER trg_orders_paid_ensure_shipment
  AFTER UPDATE OF order_status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_orders_paid_ensure_shipment();

-- ===========================================================================
-- 6. Seller / buyer RPCs
-- ===========================================================================

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
          'inspection_period'::public.delivery_status_enum,
          'completed'::public.delivery_status_enum,
          'cancelled'::public.delivery_status_enum,
          'disputed'::public.delivery_status_enum
        ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Rider details are locked after delivery verification.'
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

CREATE OR REPLACE FUNCTION public.advance_delivery(
  p_order_id uuid,
  p_action text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_action text;
  v_from public.delivery_status_enum;
  v_to public.delivery_status_enum;
  v_event text;
  v_pin_created boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_action := lower(NULLIF(btrim(COALESCE(p_action, '')), ''));
  IF v_action NOT IN ('ready_for_pickup', 'picked_up', 'out_for_delivery') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid delivery action.');
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
      'error', 'This order cannot be advanced.'
    );
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Assign a freelance rider first.'
    );
  END IF;

  v_from := v_shipment.delivery_status;
  v_to := v_action::public.delivery_status_enum;

  IF v_from = v_to THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_advanced', true,
      'delivery_status', v_from
    );
  END IF;

  IF v_action = 'ready_for_pickup'
     AND v_from IS DISTINCT FROM 'rider_assigned'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Assign a freelance rider before marking ready for pickup.'
    );
  END IF;
  IF v_action = 'picked_up'
     AND v_from IS DISTINCT FROM 'ready_for_pickup'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Mark the parcel ready for pickup first.'
    );
  END IF;
  IF v_action = 'out_for_delivery'
     AND v_from IS DISTINCT FROM 'picked_up'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Mark the parcel picked up first.'
    );
  END IF;

  IF v_action = 'ready_for_pickup' THEN
    UPDATE public.shipments
    SET delivery_status = v_to,
        ready_for_pickup_at = COALESCE(ready_for_pickup_at, now())
    WHERE shipment_id = v_shipment.shipment_id
    RETURNING * INTO v_shipment;
    v_event := 'parcel_ready_for_pickup';
  ELSIF v_action = 'picked_up' THEN
    UPDATE public.shipments
    SET delivery_status = v_to,
        picked_up_at = COALESCE(picked_up_at, now())
    WHERE shipment_id = v_shipment.shipment_id
    RETURNING * INTO v_shipment;
    v_event := 'parcel_picked_up';
    PERFORM public.notify_user(
      v_order.buyer_id,
      'shipped',
      'Parcel picked up',
      'Your parcel has been picked up and is being delivered. Order #' ||
        COALESCE(v_order.order_number, '') || '.',
      jsonb_build_object('order_id', p_order_id)
    );
  ELSE
    IF v_shipment.delivery_pin_hash IS NULL
       OR v_shipment.delivery_pin_used_at IS NOT NULL
       OR (
            v_shipment.delivery_pin_expires_at IS NOT NULL
            AND v_shipment.delivery_pin_expires_at <= now()
          ) THEN
      PERFORM public.generate_delivery_pin(v_shipment.shipment_id);
      v_pin_created := true;
    END IF;

    UPDATE public.shipments
    SET delivery_status = v_to,
        out_for_delivery_at = COALESCE(out_for_delivery_at, now())
    WHERE shipment_id = v_shipment.shipment_id
    RETURNING * INTO v_shipment;
    v_event := 'parcel_out_for_delivery';

    PERFORM public.notify_user(
      v_order.buyer_id,
      'shipped',
      'Out for delivery',
      'Your order is out for delivery. Your Delivery PIN is ready. '
        || 'Only provide your Delivery PIN after receiving your parcel. Order #'
        || COALESCE(v_order.order_number, '') || '.',
      jsonb_build_object('order_id', p_order_id)
    );
  END IF;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    v_event,
    v_from,
    v_to,
    CASE
      WHEN v_pin_created THEN jsonb_build_object('pin_generated', true)
      ELSE '{}'::jsonb
    END
  );

  IF v_pin_created THEN
    PERFORM public.record_delivery_event(
      v_shipment.shipment_id,
      p_order_id,
      auth.uid(),
      'delivery_pin_generated',
      v_from,
      v_to,
      '{}'::jsonb
    );
  END IF;

  PERFORM public.sync_order_status_for_delivery(p_order_id, v_to);

  RETURN jsonb_build_object(
    'success', true,
    'delivery_status', v_to,
    'pin_generated', v_pin_created
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_delivery_pin(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_pin text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery is not ready.');
  END IF;

  IF v_shipment.delivery_status IS DISTINCT FROM
       'out_for_delivery'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your Delivery PIN is not available yet.'
    );
  END IF;

  IF v_shipment.delivery_pin_used_at IS NOT NULL
     OR v_shipment.delivery_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This Delivery PIN has already been used.'
    );
  END IF;

  IF v_shipment.delivery_pin_expires_at IS NOT NULL
     AND v_shipment.delivery_pin_expires_at <= now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This Delivery PIN has expired.'
    );
  END IF;

  SELECT s.pin_code INTO v_pin
  FROM public.delivery_pin_secrets s
  WHERE s.shipment_id = v_shipment.shipment_id;

  IF v_pin IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Your Delivery PIN is not available yet.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'pin', v_pin,
    'expires_at', v_shipment.delivery_pin_expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_delivery_pin(
  p_order_id uuid,
  p_delivery_pin text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
  v_pin text;
  v_ok boolean := false;
  v_hours integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_pin := NULLIF(btrim(COALESCE(p_delivery_pin, '')), '');

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
      'error', 'This delivery cannot be verified.'
    );
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery is not ready.');
  END IF;

  IF v_shipment.delivery_verified_at IS NOT NULL
     OR v_shipment.delivery_status IN (
          'inspection_period'::public.delivery_status_enum,
          'completed'::public.delivery_status_enum
        ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_verified', true,
      'delivery_status', v_shipment.delivery_status
    );
  END IF;

  IF v_shipment.delivery_status IS DISTINCT FROM
       'out_for_delivery'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This delivery is not waiting for PIN verification.'
    );
  END IF;

  IF v_shipment.delivery_pin_locked_until IS NOT NULL
     AND v_shipment.delivery_pin_locked_until > now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Too many attempts. Try again later.',
      'locked', true
    );
  END IF;

  IF v_shipment.delivery_pin_locked_until IS NOT NULL
     AND v_shipment.delivery_pin_locked_until <= now() THEN
    UPDATE public.shipments
    SET delivery_pin_attempts = 0,
        delivery_pin_locked_until = NULL
    WHERE shipment_id = v_shipment.shipment_id
    RETURNING * INTO v_shipment;
  END IF;

  IF v_pin IS NOT NULL
     AND v_shipment.delivery_pin_hash IS NOT NULL
     AND v_shipment.delivery_pin_expires_at IS NOT NULL
     AND v_shipment.delivery_pin_expires_at > now()
     AND v_shipment.delivery_pin_hash = crypt(v_pin, v_shipment.delivery_pin_hash) THEN
    v_ok := true;
  END IF;

  IF NOT v_ok THEN
    UPDATE public.shipments
    SET delivery_pin_attempts = delivery_pin_attempts + 1,
        delivery_pin_locked_until = CASE
          WHEN delivery_pin_attempts + 1 >= 5
            THEN now() + interval '15 minutes'
          ELSE delivery_pin_locked_until
        END
    WHERE shipment_id = v_shipment.shipment_id
    RETURNING * INTO v_shipment;

    PERFORM public.record_delivery_event(
      v_shipment.shipment_id,
      p_order_id,
      auth.uid(),
      'delivery_pin_verification_failed',
      v_shipment.delivery_status,
      v_shipment.delivery_status,
      jsonb_build_object(
        'attempts', v_shipment.delivery_pin_attempts,
        'locked', v_shipment.delivery_pin_locked_until IS NOT NULL
          AND v_shipment.delivery_pin_locked_until > now()
      )
    );

    IF v_shipment.delivery_pin_locked_until IS NOT NULL
       AND v_shipment.delivery_pin_locked_until > now() THEN
      PERFORM public.notify_user(
        v_order.buyer_id,
        'system',
        'Delivery PIN locked',
        'Too many incorrect Delivery PIN attempts were made for Order #' ||
          COALESCE(v_order.order_number, '') || '.',
        jsonb_build_object('order_id', p_order_id)
      );
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Too many attempts. Try again later.',
        'locked', true
      );
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'Incorrect Delivery PIN.'
    );
  END IF;

  v_hours := public.inspection_period_hours();

  UPDATE public.shipments
  SET delivery_verified_at = now(),
      delivery_verification_method = 'buyer_delivery_pin',
      delivery_pin_used_at = now(),
      delivery_pin_hash = NULL,
      delivery_status = 'inspection_period'::public.delivery_status_enum,
      inspection_started_at = now(),
      inspection_expires_at = now() + make_interval(hours => v_hours)
  WHERE shipment_id = v_shipment.shipment_id
  RETURNING * INTO v_shipment;

  DELETE FROM public.delivery_pin_secrets
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'delivery_pin_verified',
    'out_for_delivery'::public.delivery_status_enum,
    'inspection_period'::public.delivery_status_enum,
    jsonb_build_object('method', 'buyer_delivery_pin')
  );

  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    'inspection_period'::public.delivery_status_enum
  );

  PERFORM public.notify_user(
    v_order.buyer_id,
    'orderConfirmed',
    'Delivery verified',
    'Your delivery was successfully verified. Your inspection period has started. Order #'
      || COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );
  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Delivery PIN verified',
    'The buyer''s Delivery PIN was successfully verified for Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_verified', false,
    'delivery_status', v_shipment.delivery_status,
    'inspection_expires_at', v_shipment.inspection_expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_delivery(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_shipment public.shipments%ROWTYPE;
BEGIN
  -- TODO Phase Future: Trigger seller payout when marketplace payout
  -- architecture is implemented. This RPC only records buyer receipt.
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status IN (
       'pending'::public.order_status_enum,
       'cancelled'::public.order_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This delivery cannot be confirmed.'
    );
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_shipment.delivery_verified_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Delivery must be verified with your PIN first.'
    );
  END IF;

  IF v_shipment.buyer_confirmed_received THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_confirmed', true
    );
  END IF;

  UPDATE public.shipments
  SET buyer_confirmed_received = true,
      buyer_confirmed_received_at = now()
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'buyer_confirmed_received',
    v_shipment.delivery_status,
    v_shipment.delivery_status,
    '{}'::jsonb
  );
  PERFORM public.touch_order_for_realtime(p_order_id);

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Buyer confirmed receipt',
    'The buyer confirmed receiving the parcel for Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN jsonb_build_object('success', true, 'already_confirmed', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.report_delivery_problem(
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
  v_reason public.delivery_dispute_reason_enum;
  v_dispute_id uuid;
  v_details text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  BEGIN
    v_reason := btrim(COALESCE(p_reason, ''))::public.delivery_dispute_reason_enum;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('success', false, 'error', 'Choose a valid reason.');
  END;

  v_details := NULLIF(btrim(COALESCE(p_details, '')), '');

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_shipment
  FROM public.shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_shipment.delivery_verified_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You can report a problem during the inspection period.'
    );
  END IF;

  IF v_order.order_status = 'completed'::public.order_status_enum
     OR v_shipment.delivery_status = 'completed'::public.delivery_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order has already been completed.'
    );
  END IF;

  IF v_order.order_status = 'cancelled'::public.order_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This order was cancelled.'
    );
  END IF;

  SELECT d.dispute_id INTO v_dispute_id
  FROM public.delivery_disputes d
  WHERE d.order_id = p_order_id
    AND d.status = 'open'::public.delivery_dispute_status_enum
  LIMIT 1;

  IF v_dispute_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_reported', true,
      'dispute_id', v_dispute_id
    );
  END IF;

  INSERT INTO public.delivery_disputes (
    shipment_id, order_id, buyer_id, reason, details
  )
  VALUES (
    v_shipment.shipment_id,
    p_order_id,
    v_order.buyer_id,
    v_reason,
    v_details
  )
  RETURNING dispute_id INTO v_dispute_id;

  UPDATE public.shipments
  SET delivery_status = 'disputed'::public.delivery_status_enum
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'delivery_dispute_created',
    v_shipment.delivery_status,
    'disputed'::public.delivery_status_enum,
    jsonb_build_object('reason', v_reason::text)
  );
  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    'disputed'::public.delivery_status_enum
  );

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Delivery problem reported',
    'A delivery problem was reported for Order #' ||
      COALESCE(v_order.order_number, '') || '.',
    jsonb_build_object('order_id', p_order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_reported', false,
    'dispute_id', v_dispute_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_delivery_failed(
  p_order_id uuid,
  p_reason text
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
      delivery_failure_reason = v_reason
  WHERE shipment_id = v_shipment.shipment_id;

  PERFORM public.record_delivery_event(
    v_shipment.shipment_id,
    p_order_id,
    auth.uid(),
    'delivery_failed',
    v_shipment.delivery_status,
    'delivery_failed'::public.delivery_status_enum,
    jsonb_build_object('reason', v_reason::text)
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
  -- TODO Phase Future: Trigger seller payout after transaction completion.
  FOR v_row IN
    SELECT s.shipment_id, s.order_id
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
         'cancelled'::public.order_status_enum,
         'disputed'::public.order_status_enum
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

    UPDATE public.shipments
    SET delivery_status = 'completed'::public.delivery_status_enum,
        auto_completed = true,
        completion_reason = 'delivery_verified_no_dispute',
        completed_at = now()
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
      'Transaction completed',
      'The transaction has been completed for Order #' ||
        COALESCE(v_order.order_number, '') || '.',
      jsonb_build_object('order_id', v_row.order_id)
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ===========================================================================
-- 7. Grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.inspection_period_hours()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.inspection_period_hours()
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.normalize_ph_mobile(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_ph_mobile(text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.order_has_paid_payment(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.order_has_paid_payment(uuid)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.touch_order_for_realtime(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.touch_order_for_realtime(uuid)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.record_delivery_event(
  uuid, uuid, uuid, text, public.delivery_status_enum, public.delivery_status_enum, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_delivery_event(
  uuid, uuid, uuid, text, public.delivery_status_enum, public.delivery_status_enum, jsonb
) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.sync_order_status_for_delivery(
  uuid, public.delivery_status_enum
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_order_status_for_delivery(
  uuid, public.delivery_status_enum
) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.generate_delivery_pin(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_delivery_pin(uuid)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.ensure_paid_shipment(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_paid_shipment(uuid)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.trg_orders_paid_ensure_shipment()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.assign_freelance_rider(
  uuid, text, text, text, text, timestamptz, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_freelance_rider(
  uuid, text, text, text, text, timestamptz, text
) TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.advance_delivery(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.advance_delivery(uuid, text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.get_my_delivery_pin(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_delivery_pin(uuid)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.verify_delivery_pin(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_delivery_pin(uuid, text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.confirm_delivery(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_delivery(uuid)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.report_delivery_problem(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_delivery_problem(uuid, text, text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.mark_delivery_failed(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_delivery_failed(uuid, text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.complete_expired_inspections()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_expired_inspections()
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 8. Realtime
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'shipments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.shipments;
  END IF;
END $$;

-- ===========================================================================
-- 9. Backfill existing paid (and later) orders
-- ===========================================================================

INSERT INTO public.shipments (order_id, delivery_status, completed_at, completion_reason)
SELECT o.order_id,
       CASE o.order_status
         WHEN 'shipped'::public.order_status_enum
           THEN 'picked_up'::public.delivery_status_enum
         WHEN 'delivered'::public.order_status_enum
           THEN 'inspection_period'::public.delivery_status_enum
         WHEN 'completed'::public.order_status_enum
           THEN 'completed'::public.delivery_status_enum
         WHEN 'disputed'::public.order_status_enum
           THEN 'disputed'::public.delivery_status_enum
         ELSE 'seller_preparing'::public.delivery_status_enum
       END,
       CASE
         WHEN o.order_status = 'completed'::public.order_status_enum
           THEN COALESCE(o.updated_at, now())
         ELSE NULL
       END,
       CASE
         WHEN o.order_status = 'completed'::public.order_status_enum
           THEN 'legacy_backfill'
         ELSE NULL
       END
FROM public.orders o
WHERE o.order_status IN (
        'paid'::public.order_status_enum,
        'shipped'::public.order_status_enum,
        'delivered'::public.order_status_enum,
        'completed'::public.order_status_enum,
        'disputed'::public.order_status_enum
      )
  AND public.order_has_paid_payment(o.order_id)
  AND NOT EXISTS (
        SELECT 1 FROM public.shipments s WHERE s.order_id = o.order_id
      );
