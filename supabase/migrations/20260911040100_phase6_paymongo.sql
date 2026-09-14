-- Phase 6 — PayMongo payment collection.
-- Apply AFTER 20260911040000_phase6_paymongo_enum.sql has committed.
-- Does not rewrite Phase 5 checkout/stock/order insert RPCs.
-- Clients still cannot INSERT/UPDATE payments or mark orders paid.

-- ===========================================================================
-- 1. payments columns + invariants
-- ===========================================================================

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS checkout_session_id text,
  ADD COLUMN IF NOT EXISTS checkout_url text,
  ADD COLUMN IF NOT EXISTS paymongo_payment_id text,
  ADD COLUMN IF NOT EXISTS amount_centavos integer,
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'PHP';

UPDATE public.payments
SET amount_centavos = round(total_amount * 100)::integer
WHERE amount_centavos IS NULL;

UPDATE public.payments
SET currency = 'PHP'
WHERE currency IS NULL OR btrim(currency) = '';

-- Collapse duplicate pending/paid rows so unique indexes can be created.
WITH ranked_pending AS (
  SELECT payment_id,
         row_number() OVER (PARTITION BY order_id ORDER BY created_at DESC) AS rn
  FROM public.payments
  WHERE payment_status = 'pending'
)
UPDATE public.payments p
SET payment_status = 'failed'::payment_status_enum
FROM ranked_pending r
WHERE p.payment_id = r.payment_id
  AND r.rn > 1;

WITH ranked_paid AS (
  SELECT payment_id,
         row_number() OVER (PARTITION BY order_id ORDER BY created_at DESC) AS rn
  FROM public.payments
  WHERE payment_status = 'paid'
)
UPDATE public.payments p
SET payment_status = 'refunded'::payment_status_enum
FROM ranked_paid r
WHERE p.payment_id = r.payment_id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS payments_one_pending_per_order
  ON public.payments (order_id)
  WHERE payment_status = 'pending'::payment_status_enum;

CREATE UNIQUE INDEX IF NOT EXISTS payments_one_paid_per_order
  ON public.payments (order_id)
  WHERE payment_status = 'paid'::payment_status_enum;

CREATE UNIQUE INDEX IF NOT EXISTS payments_checkout_session_uidx
  ON public.payments (checkout_session_id)
  WHERE checkout_session_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS payments_paymongo_payment_uidx
  ON public.payments (paymongo_payment_id)
  WHERE paymongo_payment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.paymongo_webhook_events (
  event_key text PRIMARY KEY,
  event_type text NOT NULL,
  payment_id uuid,
  order_id uuid,
  processed_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.paymongo_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paymongo_webhook_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.paymongo_webhook_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.paymongo_webhook_events TO postgres, service_role;

DROP TRIGGER IF EXISTS trg_payments_updated_at ON public.payments;
CREATE TRIGGER trg_payments_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- 2. RLS — SELECT only for participants; writes via DEFINER / service_role
-- ===========================================================================

DROP POLICY IF EXISTS payments_insert_buyer ON public.payments;
DROP POLICY IF EXISTS payments_delete_admin ON public.payments;
DROP POLICY IF EXISTS payments_update_admin ON public.payments;
DROP POLICY IF EXISTS orders_update_participant_admin ON public.orders;
DROP POLICY IF EXISTS orders_insert_buyer ON public.orders;

DROP POLICY IF EXISTS payments_select_participant ON public.payments;
DROP POLICY IF EXISTS payments_select_participant_admin ON public.payments;
CREATE POLICY payments_select_participant ON public.payments
  FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = payments.order_id
        AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS payments_insert_postgres ON public.payments;
CREATE POLICY payments_insert_postgres ON public.payments
  FOR INSERT TO postgres
  WITH CHECK (true);

DROP POLICY IF EXISTS payments_update_postgres ON public.payments;
CREATE POLICY payments_update_postgres ON public.payments
  FOR UPDATE TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.payments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.payments TO authenticated;
GRANT ALL ON TABLE public.payments TO postgres, service_role;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.orders FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.orders TO postgres, service_role;

-- ===========================================================================
-- 3. prepare_paymongo_checkout — buyer JWT, amount from the order row
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.prepare_paymongo_checkout(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_order public.orders%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_centavos integer;
  v_reuse boolean := false;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to pay.');
  END IF;

  IF p_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM v_buyer THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF v_order.order_status = 'cancelled'::order_status_enum
     OR v_order.order_status = 'disputed'::order_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order cannot be paid.');
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = v_order.order_id
      AND p.payment_status = 'paid'::payment_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id,
      'order_number', v_order.order_number
    );
  END IF;

  v_centavos := round(v_order.total_amount * 100)::integer;
  IF v_centavos IS NULL OR v_centavos < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This order has no payable amount.');
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = v_order.order_id
    AND payment_status = 'pending'::payment_status_enum
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.payments
    SET total_amount = v_order.total_amount,
        amount_centavos = v_centavos,
        currency = 'PHP',
        payment_method = 'paymongo'::payment_method_enum
    WHERE payment_id = v_payment.payment_id
    RETURNING * INTO v_payment;

    IF v_payment.checkout_session_id IS NOT NULL
       AND v_payment.checkout_url IS NOT NULL
       AND v_payment.updated_at > now() - interval '15 minutes' THEN
      v_reuse := true;
    END IF;
  ELSE
    INSERT INTO public.payments (
      order_id,
      payment_method,
      total_amount,
      payment_status,
      amount_centavos,
      currency
    )
    VALUES (
      v_order.order_id,
      'paymongo'::payment_method_enum,
      v_order.total_amount,
      'pending'::payment_status_enum,
      v_centavos,
      'PHP'
    )
    RETURNING * INTO v_payment;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'reuse', v_reuse,
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id,
    'order_number', v_order.order_number,
    'total_amount', v_order.total_amount,
    'amount_centavos', v_centavos,
    'currency', 'PHP',
    'checkout_url', CASE WHEN v_reuse THEN v_payment.checkout_url ELSE NULL END,
    'session_id', CASE WHEN v_reuse THEN v_payment.checkout_session_id ELSE NULL END,
    'previous_session_id', CASE WHEN v_reuse THEN NULL ELSE v_payment.checkout_session_id END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_paymongo_checkout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_paymongo_checkout(uuid)
  TO authenticated, postgres, service_role;

-- ===========================================================================
-- 4. attach_paymongo_checkout — store hosted session URL
-- ===========================================================================

DROP FUNCTION IF EXISTS public.attach_paymongo_checkout(uuid, text, text);
DROP FUNCTION IF EXISTS public.attach_paymongo_checkout(uuid, text, text, uuid);

CREATE OR REPLACE FUNCTION public.attach_paymongo_checkout(
  p_payment_id uuid,
  p_session_id text,
  p_checkout_url text,
  p_buyer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
BEGIN
  IF p_buyer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in to pay.');
  END IF;

  IF p_payment_id IS NULL
     OR p_session_id IS NULL OR btrim(p_session_id) = ''
     OR p_checkout_url IS NULL OR btrim(p_checkout_url) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unable to start payment right now. Please try again.');
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE payment_id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.buyer_id IS DISTINCT FROM p_buyer_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF btrim(p_session_id) NOT LIKE 'cs_%'
     OR btrim(p_checkout_url) NOT LIKE 'https://checkout.paymongo.com/%' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Unable to start payment right now. Please try again.'
    );
  END IF;

  IF v_order.order_status IS DISTINCT FROM 'pending'::order_status_enum
     OR v_payment.payment_status = 'paid'::payment_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_paid', true,
      'order_id', v_order.order_id
    );
  END IF;

  IF v_payment.payment_status IS DISTINCT FROM 'pending'::payment_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unable to start payment right now. Please try again.');
  END IF;

  UPDATE public.payments
  SET checkout_session_id = btrim(p_session_id),
      checkout_url = btrim(p_checkout_url),
      transaction_reference = btrim(p_session_id),
      payment_method = 'paymongo'::payment_method_enum
  WHERE payment_id = v_payment.payment_id;

  RETURN jsonb_build_object(
    'success', true,
    'already_paid', false,
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id,
    'session_id', btrim(p_session_id),
    'checkout_url', btrim(p_checkout_url)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.attach_paymongo_checkout(uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.attach_paymongo_checkout(uuid, text, text, uuid)
  TO postgres, service_role;

-- ===========================================================================
-- 5. apply_paymongo_event — service_role webhook only, idempotent
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.apply_paymongo_event(
  p_event_key text,
  p_event_type text,
  p_session_id text,
  p_paymongo_payment_id text,
  p_amount_centavos integer,
  p_currency text,
  p_metadata_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing public.paymongo_webhook_events%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_paid boolean := false;
  v_failed boolean := false;
  v_notified boolean := false;
  v_currency text;
BEGIN
  IF p_event_key IS NULL OR btrim(p_event_key) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing event key.');
  END IF;

  SELECT * INTO v_existing
  FROM public.paymongo_webhook_events
  WHERE event_key = p_event_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'payment_id', v_existing.payment_id,
      'order_id', v_existing.order_id
    );
  END IF;

  v_paid := p_event_type IN (
    'checkout_session.payment.paid',
    'payment.paid'
  );
  v_failed := p_event_type IN (
    'payment.failed',
    'checkout_session.payment.failed'
  );

  IF NOT v_paid AND NOT v_failed THEN
    INSERT INTO public.paymongo_webhook_events (event_key, event_type)
    VALUES (p_event_key, COALESCE(p_event_type, 'ignored'));
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;

  IF p_session_id IS NOT NULL AND btrim(p_session_id) <> '' THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE checkout_session_id = btrim(p_session_id)
       OR transaction_reference = btrim(p_session_id)
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL
     AND p_paymongo_payment_id IS NOT NULL
     AND btrim(p_paymongo_payment_id) <> '' THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE paymongo_payment_id = btrim(p_paymongo_payment_id)
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL AND p_metadata_order_id IS NOT NULL THEN
    SELECT * INTO v_payment
    FROM public.payments
    WHERE order_id = p_metadata_order_id
      AND payment_status = 'pending'::payment_status_enum
    FOR UPDATE;
  END IF;

  IF v_payment.payment_id IS NULL THEN
    IF v_failed THEN
      INSERT INTO public.paymongo_webhook_events (event_key, event_type)
      VALUES (p_event_key, COALESCE(p_event_type, 'payment.failed'))
      ON CONFLICT (event_key) DO NOTHING;
      RETURN jsonb_build_object('success', true, 'ignored', true);
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Payment not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  IF p_metadata_order_id IS NOT NULL
     AND p_metadata_order_id IS DISTINCT FROM v_order.order_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order mismatch.');
  END IF;

  v_currency := upper(COALESCE(NULLIF(btrim(p_currency), ''), 'PHP'));
  IF v_currency IS DISTINCT FROM 'PHP' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Currency mismatch.');
  END IF;

  IF v_paid THEN
    IF p_amount_centavos IS NULL
       OR p_amount_centavos IS DISTINCT FROM v_payment.amount_centavos THEN
      RETURN jsonb_build_object('success', false, 'error', 'Amount mismatch.');
    END IF;

    UPDATE public.payments
    SET payment_status = 'paid'::payment_status_enum,
        paymongo_payment_id = COALESCE(
          NULLIF(btrim(COALESCE(p_paymongo_payment_id, '')), ''),
          paymongo_payment_id
        ),
        transaction_reference = COALESCE(
          NULLIF(btrim(COALESCE(p_session_id, '')), ''),
          transaction_reference
        )
    WHERE payment_id = v_payment.payment_id
      AND payment_status IS DISTINCT FROM 'paid'::payment_status_enum;

    IF v_order.order_status = 'pending'::order_status_enum THEN
      UPDATE public.orders
      SET order_status = 'paid'::order_status_enum
      WHERE order_id = v_order.order_id
        AND order_status = 'pending'::order_status_enum;

      IF FOUND THEN
        PERFORM public.notify_user(
          v_order.buyer_id,
          'orderConfirmed',
          'Payment successful',
          'Your payment for Order #' || COALESCE(v_order.order_number, '') ||
            ' has been confirmed.',
          jsonb_build_object('order_id', v_order.order_id)
        );
        PERFORM public.notify_user(
          v_order.seller_id,
          'system',
          'Payment received',
          'Order #' || COALESCE(v_order.order_number, '') ||
            ' is paid and ready for preparation.',
          jsonb_build_object('order_id', v_order.order_id)
        );
        v_notified := true;
      END IF;
    END IF;
  ELSIF v_failed THEN
    IF v_payment.payment_status = 'pending'::payment_status_enum THEN
      UPDATE public.payments
      SET payment_status = 'failed'::payment_status_enum
      WHERE payment_id = v_payment.payment_id
        AND payment_status = 'pending'::payment_status_enum;
    END IF;
  END IF;

  INSERT INTO public.paymongo_webhook_events (
    event_key, event_type, payment_id, order_id
  )
  VALUES (
    p_event_key,
    COALESCE(p_event_type, 'unknown'),
    v_payment.payment_id,
    v_order.order_id
  )
  ON CONFLICT (event_key) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'duplicate', false,
    'paid', v_paid,
    'failed', v_failed,
    'notified', v_notified,
    'payment_id', v_payment.payment_id,
    'order_id', v_order.order_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_paymongo_event(
  text, text, text, text, integer, text, uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paymongo_event(
  text, text, text, text, integer, text, uuid
) TO postgres, service_role;

-- ===========================================================================
-- 6. Realtime so buyer/seller UIs pick up paid without restarting
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
  END IF;
END $$;
