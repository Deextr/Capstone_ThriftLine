-- Return pickup PIN follow-up: arrange_return_rider() calls generate_return_pin(),
-- which uses pgcrypto (gen_random_bytes, crypt, gen_salt) with
-- search_path = public, pg_temp only. On Supabase, pgcrypto lives in the
-- extensions schema, so saving a return rider raised:
--   function gen_random_bytes(integer) does not exist (42883)
--
-- Do not edit the applied return_pickup_pin migration. Mirror delivery PIN fix.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER FUNCTION public.generate_return_pin(uuid)
  SET search_path = public, extensions, pg_temp;

ALTER FUNCTION public.verify_return_pickup_pin(uuid, text)
  SET search_path = public, extensions, pg_temp;
