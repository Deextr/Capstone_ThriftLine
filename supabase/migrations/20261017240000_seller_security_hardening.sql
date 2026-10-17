-- SEL-001 follows privacy, SEL-002 delivery PIN hash column grants,
-- SEL-003 product price/name/stock constraints.

BEGIN;

-- ===========================================================================
-- SEL-002: Hide delivery_pin_hash from authenticated clients (keep RPC verify).
-- PostgREST order→shipment embeds need SELECT on shipments; use column grants.
-- ===========================================================================

REVOKE SELECT ON TABLE public.shipments FROM PUBLIC, anon, authenticated;

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
  delivery_failure_details,
  auto_completed,
  completion_reason,
  completed_at,
  created_at,
  updated_at
) ON public.shipments TO authenticated;

-- ===========================================================================
-- SEL-001: Restrict follows rows to the signed-in follower's own records.
-- Public follower counts use seller_profiles.follower_count (maintained by trigger).
-- ===========================================================================

DROP POLICY IF EXISTS follows_select_authenticated ON public.follows;
DROP POLICY IF EXISTS follows_select_own ON public.follows;

CREATE POLICY follows_select_own ON public.follows
  FOR SELECT TO authenticated
  USING (follower_id = auth.uid());

-- ===========================================================================
-- SEL-003: Product price, name, and fixed-price stock bounds (app rules).
-- ===========================================================================

UPDATE public.products
SET name = left(
  coalesce(nullif(btrim(name), ''), 'ThriftLine listing'),
  100
)
WHERE name IS NULL
   OR btrim(name) = ''
   OR char_length(btrim(name)) > 100;

UPDATE public.products
SET price = 1
WHERE price IS NULL
   OR price <= 0;

UPDATE public.products
SET quantity_available = 0
WHERE quantity_available < 0;

UPDATE public.products
SET quantity_available = 9999
WHERE listing_type <> 'auction'::public.listing_type_enum
  AND quantity_available > 9999;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_name_len;

ALTER TABLE public.products
  ADD CONSTRAINT products_name_len
  CHECK (
    name IS NOT NULL
    AND char_length(btrim(name)) >= 1
    AND char_length(btrim(name)) <= 100
  );

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_price_positive;

ALTER TABLE public.products
  ADD CONSTRAINT products_price_positive
  CHECK (price > 0);

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_fixed_price_quantity_max;

ALTER TABLE public.products
  ADD CONSTRAINT products_fixed_price_quantity_max
  CHECK (
    listing_type = 'auction'::public.listing_type_enum
    OR quantity_available <= 9999
  );

COMMIT;
