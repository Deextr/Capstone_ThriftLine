-- Buyer delivery addresses: Philippine mobile contact 09XXXXXXXXX (11 digits).

ALTER TABLE public.addresses
  DROP CONSTRAINT IF EXISTS addresses_phone_ph_mobile_chk;

ALTER TABLE public.addresses
  ADD CONSTRAINT addresses_phone_ph_mobile_chk
  CHECK (phone_number ~ '^09[0-9]{9}$') NOT VALID;

COMMENT ON CONSTRAINT addresses_phone_ph_mobile_chk ON public.addresses IS
  'Delivery contact must be an 11-digit Philippine mobile number starting with 09.';
