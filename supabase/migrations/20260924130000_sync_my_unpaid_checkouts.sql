-- Buyer-callable unpaid checkout sync.
--
-- expire_unpaid_checkouts() already voids fixed-price pending orders older
-- than 90 minutes, but it is only invoked from prepare_paymongo_checkout.
-- After the buyer leaves payment or restarts the app, that path never runs,
-- so a reserved unpaid order can stay pending while the cart stays empty.
--
-- This RPC uses the same expire function. It does not create payments,
-- move money, or change a paid order. Idempotent.

CREATE OR REPLACE FUNCTION public.sync_my_unpaid_checkouts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM public.expire_unpaid_checkouts();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_my_unpaid_checkouts()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_my_unpaid_checkouts()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.sync_my_unpaid_checkouts() IS
  'Expires stale unpaid fixed-price checkouts using expire_unpaid_checkouts().';
