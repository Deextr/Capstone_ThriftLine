-- Fix PostgreSQL 42725: void_unpaid_checkout(uuid) is not unique.
-- The (uuid) and (uuid, boolean) SQL wrappers conflict with DEFAULT args on
-- void_unpaid_checkout(uuid, boolean, boolean) for the same call arity.
-- Keep the 3-arg implementation (defaults: restore cart true, not a PayMongo failure).

DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid);
DROP FUNCTION IF EXISTS public.void_unpaid_checkout(uuid, boolean);
