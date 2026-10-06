-- prepare_paymongo_checkout requires this helper (originally in 20261001180000).

CREATE OR REPLACE FUNCTION public.order_delivery_address_ready(p_addr jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    COALESCE(
      NULLIF(btrim(COALESCE(p_addr->>'formatted', '')), ''),
      NULLIF(btrim(COALESCE(p_addr->>'street_address', '')), '')
    ) IS NOT NULL
    AND COALESCE(p_addr->>'phone_number', '') ~ '^09[0-9]{9}$';
$$;

REVOKE ALL ON FUNCTION public.order_delivery_address_ready(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.order_delivery_address_ready(jsonb)
  TO authenticated, postgres, service_role;
