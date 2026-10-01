-- Do not void a checkout the buyer is still paying for.
-- restore_my_unpaid_fixed_price_checkouts stays buyer-callable from Cart.
-- sync_my_unpaid_checkouts only expires stale/auction windows.
-- Idempotent. Do not edit earlier migrations.

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
  PERFORM public.expire_auction_payment_offers();
  PERFORM public.close_auctions();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_my_unpaid_checkouts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_my_unpaid_checkouts()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.sync_my_unpaid_checkouts() IS
  'Expires stale unpaid checkouts and auction payment windows. Does not void an open checkout the buyer is paying.';
