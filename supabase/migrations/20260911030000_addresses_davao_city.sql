-- Migration: 20260911030000_addresses_davao_city.sql
-- Description: Buyer delivery addresses are Davao City only.
-- Clients cannot persist a different city by editing the payload.

UPDATE public.addresses
SET city = 'Davao City'
WHERE btrim(COALESCE(city, '')) IS DISTINCT FROM 'Davao City';

CREATE OR REPLACE FUNCTION public.enforce_address_davao_city()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.city := 'Davao City';
  IF btrim(COALESCE(NEW.barangay, '')) = '' THEN
    RAISE EXCEPTION 'BARANGAY_REQUIRED';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_addresses_davao_city ON public.addresses;
CREATE TRIGGER trg_addresses_davao_city
  BEFORE INSERT OR UPDATE OF city, barangay
  ON public.addresses
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_address_davao_city();

ALTER TABLE public.addresses
  DROP CONSTRAINT IF EXISTS addresses_city_davao_check;

ALTER TABLE public.addresses
  ADD CONSTRAINT addresses_city_davao_check
  CHECK (city = 'Davao City');
