-- Reusable seller rider profiles for Arrange Delivery (shipment rows remain snapshots).

CREATE TABLE IF NOT EXISTS public.seller_saved_riders (
  saved_rider_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  rider_name text NOT NULL,
  rider_phone text NOT NULL,
  vehicle_type text NOT NULL,
  plate_number text NOT NULL,
  default_delivery_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seller_saved_riders_name_len CHECK (char_length(btrim(rider_name)) >= 2),
  CONSTRAINT seller_saved_riders_vehicle_type CHECK (
    vehicle_type IN ('motorcycle', 'car', 'van', 'bicycle', 'other')
  ),
  CONSTRAINT seller_saved_riders_plate_len CHECK (char_length(btrim(plate_number)) >= 1)
);

CREATE INDEX IF NOT EXISTS seller_saved_riders_seller_id_idx
  ON public.seller_saved_riders (seller_id);

CREATE OR REPLACE FUNCTION public.seller_saved_riders_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_phone text;
  v_name text;
BEGIN
  v_name := NULLIF(btrim(COALESCE(NEW.rider_name, '')), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Enter the rider name.'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.rider_name := v_name;

  v_phone := public.normalize_ph_mobile(NEW.rider_phone);
  IF v_phone IS NULL THEN
    RAISE EXCEPTION 'Enter a valid Philippine mobile number.'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.rider_phone := v_phone;

  NEW.vehicle_type := lower(btrim(COALESCE(NEW.vehicle_type, '')));
  NEW.plate_number := btrim(COALESCE(NEW.plate_number, ''));
  NEW.default_delivery_notes :=
    NULLIF(btrim(COALESCE(NEW.default_delivery_notes, '')), '');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seller_saved_riders_before_write
  ON public.seller_saved_riders;
CREATE TRIGGER trg_seller_saved_riders_before_write
BEFORE INSERT OR UPDATE ON public.seller_saved_riders
FOR EACH ROW EXECUTE FUNCTION public.seller_saved_riders_before_write();

DROP TRIGGER IF EXISTS trg_seller_saved_riders_updated_at
  ON public.seller_saved_riders;
CREATE TRIGGER trg_seller_saved_riders_updated_at
BEFORE UPDATE ON public.seller_saved_riders
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seller_saved_riders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_saved_riders FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seller_saved_riders_select_own ON public.seller_saved_riders;
CREATE POLICY seller_saved_riders_select_own ON public.seller_saved_riders
  FOR SELECT USING (auth.uid() = seller_id);

DROP POLICY IF EXISTS seller_saved_riders_insert_own ON public.seller_saved_riders;
CREATE POLICY seller_saved_riders_insert_own ON public.seller_saved_riders
  FOR INSERT WITH CHECK (auth.uid() = seller_id);

DROP POLICY IF EXISTS seller_saved_riders_update_own ON public.seller_saved_riders;
CREATE POLICY seller_saved_riders_update_own ON public.seller_saved_riders
  FOR UPDATE
  USING (auth.uid() = seller_id)
  WITH CHECK (auth.uid() = seller_id);

DROP POLICY IF EXISTS seller_saved_riders_delete_own ON public.seller_saved_riders;
CREATE POLICY seller_saved_riders_delete_own ON public.seller_saved_riders
  FOR DELETE USING (auth.uid() = seller_id);

REVOKE ALL ON public.seller_saved_riders FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_saved_riders TO authenticated;
