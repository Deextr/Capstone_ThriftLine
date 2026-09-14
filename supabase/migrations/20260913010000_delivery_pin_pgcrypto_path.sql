-- Phase 7 follow-up: delivery PIN generation failed at runtime because
-- generate_delivery_pin() called unqualified pgcrypto functions
-- (gen_random_bytes, crypt, gen_salt) while the caller
-- advance_delivery() sets search_path = public, pg_temp.
--
-- On Supabase, pgcrypto lives in the extensions schema, so
-- Mark Out for Delivery raised:
--   function gen_random_bytes(integer) does not exist (42883)
--
-- Do not edit the applied Phase 7 migration. Keep the same RPCs.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER FUNCTION public.generate_delivery_pin(uuid)
  SET search_path = public, extensions, pg_temp;

ALTER FUNCTION public.verify_delivery_pin(uuid, text)
  SET search_path = public, extensions, pg_temp;
