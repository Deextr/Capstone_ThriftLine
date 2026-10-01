-- Seller GCash payout destination.
--
-- Phase 10 still records payouts only. It does not send GCash.
-- request_seller_payout now requires a saved GCash method and copies
-- those details onto the payout row.
--
-- seller_payouts.status stays `requested`. That value is not a seller-facing
-- "pending" state; it is how available earnings are reduced after a request.
-- Do not drop it.
--
-- Idempotent. Do not edit earlier migrations.

CREATE TABLE IF NOT EXISTS public.seller_payout_methods (
  seller_id uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE CASCADE,
  method text NOT NULL DEFAULT 'gcash',
  account_name text NOT NULL,
  mobile_number text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seller_payout_methods_method_chk CHECK (method = 'gcash'),
  CONSTRAINT seller_payout_methods_name_chk CHECK (
    char_length(btrim(account_name)) BETWEEN 2 AND 80
  ),
  CONSTRAINT seller_payout_methods_mobile_chk CHECK (
    mobile_number ~ '^09[0-9]{9}$'
  )
);

COMMENT ON TABLE public.seller_payout_methods IS
  'Seller GCash destination for payout requests. One row per seller.';

DROP TRIGGER IF EXISTS trg_seller_payout_methods_updated_at
  ON public.seller_payout_methods;
CREATE TRIGGER trg_seller_payout_methods_updated_at
BEFORE UPDATE ON public.seller_payout_methods
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seller_payout_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_payout_methods FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seller_payout_methods_select_own
  ON public.seller_payout_methods;
CREATE POLICY seller_payout_methods_select_own
  ON public.seller_payout_methods
  FOR SELECT TO authenticated
  USING (auth.uid() = seller_id OR public.is_admin());

DROP POLICY IF EXISTS seller_payout_methods_write_own
  ON public.seller_payout_methods;
CREATE POLICY seller_payout_methods_write_own
  ON public.seller_payout_methods
  FOR ALL TO authenticated
  USING (auth.uid() = seller_id AND public.is_approved_seller())
  WITH CHECK (auth.uid() = seller_id AND public.is_approved_seller());

REVOKE ALL ON TABLE public.seller_payout_methods FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_payout_methods
  TO authenticated;
GRANT ALL ON TABLE public.seller_payout_methods TO postgres, service_role;

ALTER TABLE public.seller_payouts
  ADD COLUMN IF NOT EXISTS gcash_account_name text,
  ADD COLUMN IF NOT EXISTS gcash_mobile_number text;

CREATE OR REPLACE FUNCTION public.request_seller_payout(
  p_amount_centavos integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_available integer;
  v_amount integer;
  v_payout_id uuid;
  v_name text;
  v_mobile text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('seller-payout:' || v_uid::text));

  SELECT btrim(account_name), mobile_number
  INTO v_name, v_mobile
  FROM public.seller_payout_methods
  WHERE seller_id = v_uid
    AND method = 'gcash';

  IF v_name IS NULL OR v_mobile IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Add your GCash payment method first.'
    );
  END IF;

  v_available := public.seller_available_centavos(v_uid);
  v_amount := COALESCE(p_amount_centavos, v_available);

  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'There are no available earnings to pay out.'
    );
  END IF;

  IF v_amount < 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payouts must be at least ₱1.');
  END IF;

  IF v_amount > v_available THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You can only request up to your available earnings.'
    );
  END IF;

  INSERT INTO public.seller_payouts (
    seller_id,
    amount_centavos,
    gcash_account_name,
    gcash_mobile_number
  )
  VALUES (v_uid, v_amount, v_name, v_mobile)
  RETURNING payout_id INTO v_payout_id;

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Payout requested',
    'Your payout request of ₱' || to_char(v_amount / 100.0, 'FM999999990.00') ||
      ' was recorded for GCash ' || v_mobile || '.',
    jsonb_build_object('payout_id', v_payout_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'payout_id', v_payout_id,
    'amount_centavos', v_amount,
    'available_centavos', public.seller_available_centavos(v_uid)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_seller_payout(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_seller_payout(integer) TO authenticated;
