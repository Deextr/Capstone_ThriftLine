-- Return pickup PIN: seller shares PIN with rider; buyer verifies handoff.
-- Refund money and physical return stay independent. Idempotent.

ALTER TABLE public.return_shipments
  ADD COLUMN IF NOT EXISTS return_pin_hash text,
  ADD COLUMN IF NOT EXISTS return_pin_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS return_pin_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS return_pin_locked_until timestamptz,
  ADD COLUMN IF NOT EXISTS return_pin_used_at timestamptz,
  ADD COLUMN IF NOT EXISTS return_pin_verified_by uuid
    REFERENCES public.users (user_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS return_pin_verified_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'return_shipments_pin_attempts_chk'
      AND conrelid = 'public.return_shipments'::regclass
  ) THEN
    ALTER TABLE public.return_shipments
      ADD CONSTRAINT return_shipments_pin_attempts_chk
      CHECK (return_pin_attempts >= 0);
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE TABLE IF NOT EXISTS public.return_pin_secrets (
  return_id uuid PRIMARY KEY
    REFERENCES public.return_shipments (return_id) ON DELETE CASCADE,
  pin_code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.return_pin_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_pin_secrets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS return_pin_secrets_write_postgres ON public.return_pin_secrets;
CREATE POLICY return_pin_secrets_write_postgres ON public.return_pin_secrets
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.return_pin_secrets FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.return_pin_secrets TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.generate_return_pin(p_return_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n bigint;
  v_pin text;
BEGIN
  IF p_return_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_n := ('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint;
  v_pin := lpad((v_n % 1000000)::text, 6, '0');

  UPDATE public.return_shipments
  SET
    return_pin_hash = crypt(v_pin, gen_salt('bf')),
    return_pin_expires_at = now() + interval '7 days',
    return_pin_attempts = 0,
    return_pin_locked_until = NULL,
    return_pin_used_at = NULL,
    return_pin_verified_by = NULL,
    return_pin_verified_at = NULL
  WHERE return_id = p_return_id;

  INSERT INTO public.return_pin_secrets (return_id, pin_code)
  VALUES (p_return_id, v_pin)
  ON CONFLICT (return_id) DO UPDATE
  SET pin_code = EXCLUDED.pin_code,
      created_at = now();

  RETURN v_pin;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_return_pin(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_return_pin(uuid) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.get_my_return_pin(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
  v_pin text;
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

  IF NOT v_row.return_required
     OR v_row.status IS DISTINCT FROM 'rider_assigned'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The pickup PIN is available after you assign a return rider.'
    );
  END IF;

  IF v_row.return_pin_used_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This pickup PIN has already been used.'
    );
  END IF;

  IF v_row.return_pin_expires_at IS NOT NULL
     AND v_row.return_pin_expires_at <= now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This pickup PIN has expired. Update the rider to get a new PIN.'
    );
  END IF;

  SELECT s.pin_code INTO v_pin
  FROM public.return_pin_secrets s
  WHERE s.return_id = v_row.return_id;

  IF v_pin IS NULL OR v_row.return_pin_hash IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Pickup PIN is not ready yet.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'pin', v_pin,
    'expires_at', v_row.return_pin_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_return_pin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_return_pin(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_return_pickup_pin(
  p_order_id uuid,
  p_pickup_pin text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
  v_pin text;
  v_ok boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  v_pin := NULLIF(btrim(COALESCE(p_pickup_pin, '')), '');

  IF v_pin IS NULL OR char_length(v_pin) <> 6 OR v_pin !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Enter the 6-digit pickup PIN from the rider.'
    );
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_row.buyer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Return not found.');
  END IF;

  IF NOT v_row.return_required
     OR v_row.status IS DISTINCT FROM 'rider_assigned'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Wait until a rider is assigned before entering the pickup PIN.'
    );
  END IF;

  IF v_row.return_pin_used_at IS NOT NULL
     OR v_row.status = 'picked_up'::public.return_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_status', v_row.status::text
    );
  END IF;

  IF v_row.return_pin_locked_until IS NOT NULL
     AND v_row.return_pin_locked_until > now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Too many attempts. Try again later.',
      'locked', true
    );
  END IF;

  IF v_row.return_pin_locked_until IS NOT NULL
     AND v_row.return_pin_locked_until <= now() THEN
    UPDATE public.return_shipments
    SET return_pin_attempts = 0,
        return_pin_locked_until = NULL
    WHERE return_id = v_row.return_id
    RETURNING * INTO v_row;
  END IF;

  IF v_row.return_pin_hash IS NOT NULL
     AND v_row.return_pin_expires_at IS NOT NULL
     AND v_row.return_pin_expires_at > now()
     AND v_row.return_pin_hash = crypt(v_pin, v_row.return_pin_hash) THEN
    v_ok := true;
  END IF;

  IF NOT v_ok THEN
    UPDATE public.return_shipments
    SET return_pin_attempts = return_pin_attempts + 1,
        return_pin_locked_until = CASE
          WHEN return_pin_attempts + 1 >= 5
            THEN now() + interval '15 minutes'
          ELSE return_pin_locked_until
        END
    WHERE return_id = v_row.return_id
    RETURNING * INTO v_row;

    IF v_row.return_pin_locked_until IS NOT NULL
       AND v_row.return_pin_locked_until > now() THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Too many attempts. Try again later.',
        'locked', true
      );
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'Incorrect pickup PIN. Check the code from the rider.'
    );
  END IF;

  UPDATE public.return_shipments
  SET
    status = 'picked_up'::public.return_status_enum,
    picked_up_at = now(),
    return_pin_used_at = now(),
    return_pin_verified_by = auth.uid(),
    return_pin_verified_at = now()
  WHERE return_id = v_row.return_id
    AND status = 'rider_assigned'::public.return_status_enum;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record the handoff.');
  END IF;

  PERFORM public.notify_user(
    v_row.seller_id,
    'system',
    'Return in transit',
    'The buyer verified the pickup PIN. Confirm when you receive the item.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_status', 'picked_up'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_return_pickup_pin(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_return_pickup_pin(uuid, text) TO authenticated;

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

  PERFORM public.generate_return_pin(v_row.return_id);

  PERFORM public.notify_user(
    v_row.buyer_id,
    'shipped',
    'Pickup arranged',
    v_name || ' will pick up the item. Enter the pickup PIN when the rider gives it to you.',
    jsonb_build_object('order_id', v_row.order_id)
  );
  PERFORM public.notify_user(
    v_row.seller_id,
    'system',
    'Pickup PIN ready',
    'Share the pickup PIN in your order with the rider. The buyer will enter it when they hand over the item.',
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
BEGIN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Enter the pickup PIN from the rider to confirm handoff.'
  );
END;
$$;

UPDATE public.shipments s
SET
  delivery_status = 'cancelled'::public.delivery_status_enum,
  completion_reason = COALESCE(s.completion_reason, 'admin_refunded_payment'),
  completed_at = COALESCE(s.completed_at, now())
FROM public.orders o
WHERE o.order_id = s.order_id
  AND o.order_status = 'cancelled'::public.order_status_enum
  AND s.delivery_status = 'disputed'::public.delivery_status_enum
  AND NOT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = s.order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  );
