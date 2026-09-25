-- Phase 10 — Held payments, release, refunds, payout requests, appeals.
--
-- Internal ledger only. This is not a regulated third-party escrow product.
-- Buyer payment is collected by PayMongo. This table records whether that
-- paid amount is held, disputed, released to seller earnings, or refunded.
--
-- Does not add trust-score math, automatic bans, live selling, or GCash
-- disbursement to sellers.
--
-- Idempotent. Safe to re-run. Do not edit earlier migrations.

-- ===========================================================================
-- 1. Enums
-- ===========================================================================

DO $$
BEGIN
  CREATE TYPE public.escrow_status_enum AS ENUM (
    'held',
    'disputed',
    'released',
    'refunded'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  CREATE TYPE public.escrow_refund_provider_enum AS ENUM (
    'none',
    'paymongo',
    'internal'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

DO $$
BEGIN
  CREATE TYPE public.seller_payout_status_enum AS ENUM (
    'requested'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

-- ===========================================================================
-- 2. Tables
-- ===========================================================================

-- The original schema already had a stub `escrow` table (payment_id, amount,
-- escrow_status = holding/released/refunded/disputed) and escrow_status_enum.
-- CREATE TABLE IF NOT EXISTS would skip it, then indexes fail because
-- paymongo_refund_id does not exist. Replace that unused stub, then create
-- the Phase 10 ledger.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'escrow'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'escrow'
      AND column_name = 'amount_centavos'
  ) THEN
    IF EXISTS (SELECT 1 FROM public.escrow LIMIT 1) THEN
      RAISE EXCEPTION
        'public.escrow already exists in the old foundation shape and has rows. Inspect it before applying Phase 10.';
    END IF;
    DROP TABLE public.escrow CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'escrow_status_enum'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'escrow_status_enum'
      AND e.enumlabel = 'held'
  ) THEN
    DROP TYPE public.escrow_status_enum;
  END IF;
END
$$;

DO $$
BEGIN
  CREATE TYPE public.escrow_status_enum AS ENUM (
    'held',
    'disputed',
    'released',
    'refunded'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE TABLE IF NOT EXISTS public.escrow (
  escrow_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES public.orders (order_id) ON DELETE RESTRICT,
  payment_id uuid NOT NULL REFERENCES public.payments (payment_id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  amount_centavos integer NOT NULL CHECK (amount_centavos > 0),
  seller_amount_centavos integer NOT NULL CHECK (seller_amount_centavos >= 0),
  status public.escrow_status_enum NOT NULL DEFAULT 'held'::public.escrow_status_enum,
  held_at timestamptz NOT NULL DEFAULT now(),
  disputed_at timestamptz,
  released_at timestamptz,
  refunded_at timestamptz,
  release_reason text,
  refund_reason text,
  resolved_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  dispute_id uuid REFERENCES public.delivery_disputes (dispute_id) ON DELETE SET NULL,
  refund_lock_at timestamptz,
  refund_provider public.escrow_refund_provider_enum NOT NULL
    DEFAULT 'none'::public.escrow_refund_provider_enum,
  paymongo_refund_id text,
  refund_provider_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT escrow_seller_amount_lte_payment
    CHECK (seller_amount_centavos <= amount_centavos)
);

ALTER TABLE public.escrow
  ADD COLUMN IF NOT EXISTS order_id uuid,
  ADD COLUMN IF NOT EXISTS payment_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_id uuid,
  ADD COLUMN IF NOT EXISTS seller_id uuid,
  ADD COLUMN IF NOT EXISTS amount_centavos integer,
  ADD COLUMN IF NOT EXISTS seller_amount_centavos integer,
  ADD COLUMN IF NOT EXISTS status public.escrow_status_enum,
  ADD COLUMN IF NOT EXISTS held_at timestamptz,
  ADD COLUMN IF NOT EXISTS disputed_at timestamptz,
  ADD COLUMN IF NOT EXISTS released_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS release_reason text,
  ADD COLUMN IF NOT EXISTS refund_reason text,
  ADD COLUMN IF NOT EXISTS resolved_by uuid,
  ADD COLUMN IF NOT EXISTS dispute_id uuid,
  ADD COLUMN IF NOT EXISTS refund_lock_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_provider public.escrow_refund_provider_enum,
  ADD COLUMN IF NOT EXISTS paymongo_refund_id text,
  ADD COLUMN IF NOT EXISTS refund_provider_status text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS escrow_paymongo_refund_uidx
  ON public.escrow (paymongo_refund_id)
  WHERE paymongo_refund_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS escrow_seller_status_idx
  ON public.escrow (seller_id, status);

CREATE INDEX IF NOT EXISTS escrow_status_idx
  ON public.escrow (status);

DROP TRIGGER IF EXISTS trg_escrow_updated_at ON public.escrow;
CREATE TRIGGER trg_escrow_updated_at
BEFORE UPDATE ON public.escrow
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.escrow IS
  'Internal paid-order ledger. held/disputed/released/refunded. Not a legal escrow product.';

CREATE TABLE IF NOT EXISTS public.seller_payouts (
  payout_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  amount_centavos integer NOT NULL CHECK (amount_centavos > 0),
  status public.seller_payout_status_enum NOT NULL
    DEFAULT 'requested'::public.seller_payout_status_enum,
  requested_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS seller_payouts_seller_idx
  ON public.seller_payouts (seller_id, requested_at DESC);

COMMENT ON TABLE public.seller_payouts IS
  'Seller requested a payout of released earnings. Phase 10 records the request only; it does not send GCash.';

CREATE TABLE IF NOT EXISTS public.report_appeals (
  appeal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.reports (report_id) ON DELETE CASCADE,
  appellant_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE RESTRICT,
  details text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT report_appeals_details_len CHECK (
    char_length(details) BETWEEN 10 AND 2000
  ),
  CONSTRAINT report_appeals_one_per_report UNIQUE (report_id)
);

CREATE INDEX IF NOT EXISTS report_appeals_appellant_idx
  ON public.report_appeals (appellant_id, created_at DESC);

COMMENT ON TABLE public.report_appeals IS
  'Reported user may submit one short appeal after a Phase 9 decision. Does not change money or the original report.';

-- ===========================================================================
-- 3. RLS
-- ===========================================================================

ALTER TABLE public.escrow ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow FORCE ROW LEVEL SECURITY;
ALTER TABLE public.seller_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_payouts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.report_appeals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_appeals FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS escrow_select_participant ON public.escrow;
CREATE POLICY escrow_select_participant ON public.escrow
  FOR SELECT TO authenticated
  USING (
    buyer_id = auth.uid()
    OR seller_id = auth.uid()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS escrow_write_postgres ON public.escrow;
CREATE POLICY escrow_write_postgres ON public.escrow
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS seller_payouts_select_own ON public.seller_payouts;
CREATE POLICY seller_payouts_select_own ON public.seller_payouts
  FOR SELECT TO authenticated
  USING (seller_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS seller_payouts_write_postgres ON public.seller_payouts;
CREATE POLICY seller_payouts_write_postgres ON public.seller_payouts
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS report_appeals_select_own_or_admin ON public.report_appeals;
CREATE POLICY report_appeals_select_own_or_admin ON public.report_appeals
  FOR SELECT TO authenticated
  USING (appellant_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS report_appeals_write_postgres ON public.report_appeals;
CREATE POLICY report_appeals_write_postgres ON public.report_appeals
  FOR ALL TO postgres
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.escrow FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.seller_payouts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.report_appeals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.escrow TO authenticated;
GRANT SELECT ON TABLE public.seller_payouts TO authenticated;
GRANT SELECT ON TABLE public.report_appeals TO authenticated;
GRANT ALL ON TABLE public.escrow TO postgres, service_role;
GRANT ALL ON TABLE public.seller_payouts TO postgres, service_role;
GRANT ALL ON TABLE public.report_appeals TO postgres, service_role;

-- ===========================================================================
-- 4. Hold + release helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_order_escrow_hold(p_order_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_escrow_id uuid;
  v_seller_centavos integer;
  v_open boolean;
  v_status public.escrow_status_enum;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
    AND payment_status = 'paid'::public.payment_status_enum
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND OR v_payment.amount_centavos IS NULL OR v_payment.amount_centavos <= 0 THEN
    RETURN NULL;
  END IF;

  v_seller_centavos := GREATEST(
    0,
    v_payment.amount_centavos - round(COALESCE(v_order.platform_fee, 0) * 100)::integer
  );

  SELECT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = p_order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) INTO v_open;

  v_status := CASE
    WHEN v_open THEN 'disputed'::public.escrow_status_enum
    ELSE 'held'::public.escrow_status_enum
  END;

  INSERT INTO public.escrow (
    order_id,
    payment_id,
    buyer_id,
    seller_id,
    amount_centavos,
    seller_amount_centavos,
    status,
    disputed_at
  )
  VALUES (
    v_order.order_id,
    v_payment.payment_id,
    v_order.buyer_id,
    v_order.seller_id,
    v_payment.amount_centavos,
    v_seller_centavos,
    v_status,
    CASE WHEN v_open THEN now() ELSE NULL END
  )
  ON CONFLICT (order_id) DO NOTHING
  RETURNING escrow_id INTO v_escrow_id;

  IF v_escrow_id IS NULL THEN
    SELECT escrow_id INTO v_escrow_id
    FROM public.escrow
    WHERE order_id = p_order_id;
  END IF;

  RETURN v_escrow_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.try_auto_release_escrow(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_open boolean;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.order_status IS DISTINCT FROM 'completed'::public.order_status_enum THEN
    RETURN false;
  END IF;

  PERFORM public.ensure_order_escrow_hold(p_order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_escrow.status IN (
       'released'::public.escrow_status_enum,
       'refunded'::public.escrow_status_enum
     ) THEN
    RETURN v_escrow.status = 'released'::public.escrow_status_enum;
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.payment_id = v_escrow.payment_id
      AND p.payment_status = 'paid'::public.payment_status_enum
  ) THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = p_order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  ) INTO v_open;

  IF v_open THEN
    IF v_escrow.status = 'held'::public.escrow_status_enum THEN
      UPDATE public.escrow
      SET status = 'disputed'::public.escrow_status_enum,
          disputed_at = COALESCE(disputed_at, now())
      WHERE escrow_id = v_escrow.escrow_id
        AND status = 'held'::public.escrow_status_enum;
    END IF;
    RETURN false;
  END IF;

  UPDATE public.escrow
  SET
    status = 'released'::public.escrow_status_enum,
    released_at = now(),
    release_reason = COALESCE(release_reason, 'order_completed'),
    refund_lock_at = NULL
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Earnings available',
    'Payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' is now available as earnings.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_escrow_disputed(p_order_id uuid, p_dispute_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.ensure_order_escrow_hold(p_order_id);

  UPDATE public.escrow
  SET
    status = 'disputed'::public.escrow_status_enum,
    disputed_at = COALESCE(disputed_at, now()),
    dispute_id = COALESCE(p_dispute_id, dispute_id)
  WHERE order_id = p_order_id
    AND status = 'held'::public.escrow_status_enum;
END;
$$;

-- ===========================================================================
-- 5. Triggers — paid hold, dispute, auto-release
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.trg_payments_ensure_escrow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.payment_status = 'paid'::public.payment_status_enum THEN
    PERFORM public.ensure_order_escrow_hold(NEW.order_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payments_ensure_escrow ON public.payments;
CREATE TRIGGER trg_payments_ensure_escrow
AFTER INSERT OR UPDATE OF payment_status ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.trg_payments_ensure_escrow();

CREATE OR REPLACE FUNCTION public.trg_delivery_disputes_mark_escrow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'open'::public.delivery_dispute_status_enum THEN
    PERFORM public.mark_escrow_disputed(NEW.order_id, NEW.dispute_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_disputes_mark_escrow ON public.delivery_disputes;
CREATE TRIGGER trg_delivery_disputes_mark_escrow
AFTER INSERT ON public.delivery_disputes
FOR EACH ROW
EXECUTE FUNCTION public.trg_delivery_disputes_mark_escrow();

CREATE OR REPLACE FUNCTION public.trg_orders_auto_release_escrow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.order_status = 'completed'::public.order_status_enum
     AND OLD.order_status IS DISTINCT FROM 'completed'::public.order_status_enum
  THEN
    PERFORM public.try_auto_release_escrow(NEW.order_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_auto_release_escrow ON public.orders;
CREATE TRIGGER trg_orders_auto_release_escrow
AFTER UPDATE OF order_status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_auto_release_escrow();

-- ===========================================================================
-- 6. Admin money decision
-- ===========================================================================

CREATE OR REPLACE FUNCTION public._close_open_dispute(
  p_dispute_id uuid,
  p_admin_id uuid,
  p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.delivery_disputes
  SET
    status = 'resolved'::public.delivery_dispute_status_enum,
    admin_note = COALESCE(p_note, admin_note),
    reviewed_by = COALESCE(p_admin_id, reviewed_by),
    resolved_at = COALESCE(resolved_at, now())
  WHERE dispute_id = p_dispute_id
    AND status = 'open'::public.delivery_dispute_status_enum;
END;
$$;

CREATE OR REPLACE FUNCTION public._complete_order_after_release(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.shipments
  SET
    delivery_status = 'completed'::public.delivery_status_enum,
    completion_reason = COALESCE(completion_reason, 'admin_released_payment'),
    completed_at = COALESCE(completed_at, now())
  WHERE order_id = p_order_id
    AND delivery_status IS DISTINCT FROM 'completed'::public.delivery_status_enum
    AND delivery_status IS DISTINCT FROM 'cancelled'::public.delivery_status_enum;

  PERFORM public.sync_order_status_for_delivery(
    p_order_id,
    'completed'::public.delivery_status_enum
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_delivery_payment(
  p_dispute_id uuid,
  p_decision text,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_note text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can resolve this payment.'
    );
  END IF;

  v_decision := lower(trim(coalesce(p_decision, '')));
  IF v_decision IS DISTINCT FROM 'release' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a valid payment decision.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 2,000 characters.');
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
  END IF;

  PERFORM public.ensure_order_escrow_hold(v_order.order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'release',
      'status', 'released',
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already refunded to the buyer.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A refund is already in progress for this payment.'
    );
  END IF;

  UPDATE public.escrow
  SET
    status = 'released'::public.escrow_status_enum,
    released_at = COALESCE(released_at, now()),
    release_reason = 'admin_release',
    resolved_by = v_uid,
    dispute_id = v_dispute.dispute_id,
    refund_lock_at = NULL
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  IF NOT FOUND THEN
    SELECT status INTO v_escrow.status FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
    IF v_escrow.status = 'released'::public.escrow_status_enum THEN
      PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);
      RETURN jsonb_build_object(
        'success', true,
        'already_decided', true,
        'decision', 'release',
        'status', 'released',
        'amount_centavos', v_escrow.amount_centavos
      );
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Could not release this payment.');
  END IF;

  PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);
  PERFORM public._complete_order_after_release(v_order.order_id);

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Earnings available',
    'Payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' is now available as earnings.',
    jsonb_build_object('order_id', v_order.order_id)
  );
  PERFORM public.notify_user(
    v_order.buyer_id,
    'orderConfirmed',
    'Delivery problem closed',
    'The held payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' stays with the seller.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'release',
    'status', 'released',
    'amount_centavos', v_escrow.amount_centavos,
    'seller_amount_centavos', v_escrow.seller_amount_centavos
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_delivery_refund(
  p_dispute_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_note text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_payment public.payments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can refund this payment.'
    );
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 2,000 characters.');
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  PERFORM public.ensure_order_escrow_hold(v_order.order_id);

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE payment_id = v_escrow.payment_id
  FOR UPDATE;

  UPDATE public.escrow
  SET
    refund_lock_at = COALESCE(refund_lock_at, now()),
    refund_reason = COALESCE(v_note, refund_reason, 'admin_refund'),
    resolved_by = v_uid,
    dispute_id = v_dispute.dispute_id
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'needs_provider_refund', true,
    'dispute_id', v_dispute.dispute_id,
    'order_id', v_order.order_id,
    'escrow_id', v_escrow.escrow_id,
    'amount_centavos', v_escrow.amount_centavos,
    'paymongo_payment_id', v_payment.paymongo_payment_id,
    'admin_note', v_note
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.abort_delivery_refund(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dispute public.delivery_disputes%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can cancel this refund attempt.');
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  UPDATE public.escrow
  SET refund_lock_at = NULL
  WHERE order_id = v_dispute.order_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
    AND refunded_at IS NULL
    AND paymongo_refund_id IS NULL;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_delivery_refund(
  p_dispute_id uuid,
  p_provider text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_provider text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_note text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can refund this payment.');
  END IF;

  v_provider := lower(trim(coalesce(p_provider, '')));
  IF v_provider NOT IN ('paymongo', 'internal') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown refund provider.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);

  UPDATE public.escrow
  SET
    status = 'refunded'::public.escrow_status_enum,
    refunded_at = now(),
    refund_reason = COALESCE(v_note, refund_reason, 'admin_refund'),
    resolved_by = v_uid,
    dispute_id = v_dispute.dispute_id,
    refund_lock_at = NULL,
    refund_provider = v_provider::public.escrow_refund_provider_enum,
    paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    refund_provider_status = COALESCE(NULLIF(btrim(coalesce(p_provider_status, '')), ''), v_provider)
  WHERE escrow_id = v_escrow.escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record this refund.');
  END IF;

  UPDATE public.payments
  SET payment_status = 'refunded'::public.payment_status_enum
  WHERE payment_id = v_escrow.payment_id
    AND payment_status = 'paid'::public.payment_status_enum;

  UPDATE public.shipments
  SET
    delivery_status = 'cancelled'::public.delivery_status_enum,
    completion_reason = COALESCE(completion_reason, 'admin_refunded_payment'),
    completed_at = COALESCE(completed_at, now())
  WHERE order_id = v_order.order_id
    AND delivery_status IS DISTINCT FROM 'cancelled'::public.delivery_status_enum;

  UPDATE public.orders
  SET order_status = 'cancelled'::public.order_status_enum,
      updated_at = now()
  WHERE order_id = v_order.order_id
    AND order_status IS DISTINCT FROM 'cancelled'::public.order_status_enum;

  PERFORM public.notify_user(
    v_order.buyer_id,
    'orderConfirmed',
    CASE
      WHEN v_provider = 'paymongo' THEN 'Refund sent'
      ELSE 'Refund recorded'
    END,
    CASE
      WHEN v_provider = 'paymongo' THEN
        'The payment for Order #' || COALESCE(v_order.order_number, '') ||
        ' is being returned through the original payment method.'
      ELSE
        'ThriftLine recorded a refund for Order #' || COALESCE(v_order.order_number, '') ||
        '. The payment provider did not process an automatic refund.'
    END,
    jsonb_build_object(
      'order_id', v_order.order_id,
      'refund_provider', v_provider
    )
  );
  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Payment refunded',
    'The held payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' was refunded to the buyer and is not available as earnings.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'refund',
    'status', 'refunded',
    'refund_provider', v_provider,
    'amount_centavos', v_escrow.amount_centavos
  );
END;
$$;

-- ===========================================================================
-- 7. Seller earnings + payout
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.seller_available_centavos(p_seller_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT GREATEST(
    0,
    COALESCE((
      SELECT SUM(seller_amount_centavos)
      FROM public.escrow
      WHERE seller_id = p_seller_id
        AND status = 'released'::public.escrow_status_enum
    ), 0)::integer
    -
    COALESCE((
      SELECT SUM(amount_centavos)
      FROM public.seller_payouts
      WHERE seller_id = p_seller_id
        AND status = 'requested'::public.seller_payout_status_enum
    ), 0)::integer
  );
$$;

CREATE OR REPLACE FUNCTION public.seller_earnings_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_held integer := 0;
  v_released integer := 0;
  v_refunded integer := 0;
  v_payout integer := 0;
  v_listings integer := 0;
  v_activity jsonb := '[]'::jsonb;
  v_payouts jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  SELECT COALESCE(SUM(seller_amount_centavos) FILTER (
           WHERE status IN (
             'held'::public.escrow_status_enum,
             'disputed'::public.escrow_status_enum
           )
         ), 0),
         COALESCE(SUM(seller_amount_centavos) FILTER (
           WHERE status = 'released'::public.escrow_status_enum
         ), 0),
         COALESCE(SUM(seller_amount_centavos) FILTER (
           WHERE status = 'refunded'::public.escrow_status_enum
         ), 0)
  INTO v_held, v_released, v_refunded
  FROM public.escrow
  WHERE seller_id = v_uid;

  SELECT COALESCE(SUM(amount_centavos), 0)
  INTO v_payout
  FROM public.seller_payouts
  WHERE seller_id = v_uid
    AND status = 'requested'::public.seller_payout_status_enum;

  SELECT COUNT(*) INTO v_listings
  FROM public.products
  WHERE seller_id = v_uid
    AND status IS DISTINCT FROM 'removed'::public.product_status_enum;

  SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.sort_at DESC), '[]'::jsonb)
  INTO v_activity
  FROM (
    SELECT jsonb_build_object(
      'escrow_id', e.escrow_id,
      'order_id', e.order_id,
      'order_number', o.order_number,
      'title', COALESCE((
        SELECT oi.title
        FROM public.order_items oi
        WHERE oi.order_id = e.order_id
        ORDER BY oi.created_at
        LIMIT 1
      ), 'Order'),
      'status', e.status::text,
      'seller_amount_centavos', e.seller_amount_centavos,
      'amount_centavos', e.amount_centavos,
      'sort_at', COALESCE(e.released_at, e.refunded_at, e.disputed_at, e.held_at)
    ) AS item,
    COALESCE(e.released_at, e.refunded_at, e.disputed_at, e.held_at) AS sort_at
    FROM public.escrow e
    JOIN public.orders o ON o.order_id = e.order_id
    WHERE e.seller_id = v_uid
    ORDER BY COALESCE(e.released_at, e.refunded_at, e.disputed_at, e.held_at) DESC
    LIMIT 20
  ) listed;

  SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.sort_at DESC), '[]'::jsonb)
  INTO v_payouts
  FROM (
    SELECT jsonb_build_object(
      'payout_id', p.payout_id,
      'amount_centavos', p.amount_centavos,
      'status', p.status::text,
      'requested_at', p.requested_at,
      'sort_at', p.requested_at
    ) AS item,
    p.requested_at AS sort_at
    FROM public.seller_payouts p
    WHERE p.seller_id = v_uid
    ORDER BY p.requested_at DESC
    LIMIT 10
  ) listed;

  RETURN jsonb_build_object(
    'success', true,
    'held_centavos', v_held,
    'released_centavos', v_released,
    'refunded_centavos', v_refunded,
    'payout_requested_centavos', v_payout,
    'available_centavos', GREATEST(0, v_released - v_payout),
    'listing_count', v_listings,
    'activity', v_activity,
    'payouts', v_payouts
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_seller_payout(p_amount_centavos integer DEFAULT NULL)
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('seller-payout:' || v_uid::text));

  v_available := public.seller_available_centavos(v_uid);
  v_amount := COALESCE(p_amount_centavos, v_available);

  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'There are no available earnings to pay out.');
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

  INSERT INTO public.seller_payouts (seller_id, amount_centavos)
  VALUES (v_uid, v_amount)
  RETURNING payout_id INTO v_payout_id;

  PERFORM public.notify_user(
    v_uid,
    'system',
    'Payout requested',
    'Your payout request was recorded. This does not send GCash automatically.',
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

-- ===========================================================================
-- 8. Community report: notify reported user + appeal
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.notify_report_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'under_review'::public.report_status_enum
     AND NEW.status IS DISTINCT FROM 'under_review'::public.report_status_enum
  THEN
    PERFORM public.notify_user(
      NEW.reporter_id,
      'report_decision',
      'Report update',
      'We reviewed your report. Open My Reports to see the decision.',
      jsonb_build_object(
        'report_id', NEW.report_id,
        'status', NEW.status::text
      )
    );
    PERFORM public.notify_user(
      NEW.reported_user_id,
      'system',
      'Account review update',
      'A community report involving your account has been reviewed. Reporter details are not shared.',
      jsonb_build_object(
        'report_id', NEW.report_id,
        'can_appeal', true
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_report_appeal(
  p_report_id uuid,
  p_details text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_details text;
  v_report public.reports%ROWTYPE;
  v_appeal_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_report_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  v_details := trim(coalesce(p_details, ''));
  IF char_length(v_details) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please add a bit more detail.');
  END IF;
  IF char_length(v_details) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep your appeal under 2,000 characters.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND OR v_report.reported_user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can only appeal a review of your account.');
  END IF;

  IF v_report.status = 'under_review'::public.report_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'This report is still under review.');
  END IF;

  INSERT INTO public.report_appeals (report_id, appellant_id, details)
  VALUES (p_report_id, v_uid, v_details)
  ON CONFLICT (report_id) DO NOTHING
  RETURNING appeal_id INTO v_appeal_id;

  IF v_appeal_id IS NULL THEN
    SELECT appeal_id INTO v_appeal_id
    FROM public.report_appeals
    WHERE report_id = p_report_id
      AND appellant_id = v_uid;
    RETURN jsonb_build_object(
      'success', true,
      'already_submitted', true,
      'appeal_id', v_appeal_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_submitted', false,
    'appeal_id', v_appeal_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_report_appeal_context(p_report_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_report public.reports%ROWTYPE;
  v_appeal public.report_appeals%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF p_report_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Review not found.');
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id;

  IF NOT FOUND OR v_report.reported_user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can only appeal a review of your account.');
  END IF;

  IF v_report.status = 'under_review'::public.report_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'can_appeal', false,
      'already_submitted', false,
      'under_review', true
    );
  END IF;

  SELECT * INTO v_appeal
  FROM public.report_appeals
  WHERE report_id = p_report_id
    AND appellant_id = v_uid;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'can_appeal', false,
      'already_submitted', true,
      'under_review', false,
      'appeal_id', v_appeal.appeal_id,
      'details', v_appeal.details,
      'created_at', v_appeal.created_at
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'can_appeal', true,
    'already_submitted', false,
    'under_review', false
  );
END;
$$;

-- ===========================================================================
-- 9. Grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.ensure_order_escrow_hold(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_order_escrow_hold(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.try_auto_release_escrow(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.try_auto_release_escrow(uuid) TO postgres, service_role, authenticated;

REVOKE ALL ON FUNCTION public.mark_escrow_disputed(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_escrow_disputed(uuid, uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public.resolve_delivery_payment(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_delivery_payment(uuid, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.prepare_delivery_refund(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_delivery_refund(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.abort_delivery_refund(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abort_delivery_refund(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.finalize_delivery_refund(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_delivery_refund(uuid, text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.seller_earnings_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_earnings_snapshot() TO authenticated;

REVOKE ALL ON FUNCTION public.request_seller_payout(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_seller_payout(integer) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_report_appeal(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_report_appeal(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.get_report_appeal_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_appeal_context(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.seller_available_centavos(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seller_available_centavos(uuid) TO postgres, service_role;

REVOKE ALL ON FUNCTION public._close_open_dispute(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._complete_order_after_release(uuid) FROM PUBLIC, anon, authenticated;

-- ===========================================================================
-- 10. Backfill existing paid orders
-- ===========================================================================

INSERT INTO public.escrow (
  order_id,
  payment_id,
  buyer_id,
  seller_id,
  amount_centavos,
  seller_amount_centavos,
  status,
  held_at,
  disputed_at
)
SELECT
  o.order_id,
  p.payment_id,
  o.buyer_id,
  o.seller_id,
  p.amount_centavos,
  GREATEST(
    0,
    p.amount_centavos - round(COALESCE(o.platform_fee, 0) * 100)::integer
  ),
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = o.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    ) THEN 'disputed'::public.escrow_status_enum
    ELSE 'held'::public.escrow_status_enum
  END,
  COALESCE(p.updated_at, p.created_at, now()),
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.delivery_disputes d
      WHERE d.order_id = o.order_id
        AND d.status = 'open'::public.delivery_dispute_status_enum
    ) THEN now()
    ELSE NULL
  END
FROM public.payments p
JOIN public.orders o ON o.order_id = p.order_id
WHERE p.payment_status = 'paid'::public.payment_status_enum
  AND p.amount_centavos IS NOT NULL
  AND p.amount_centavos > 0
ON CONFLICT (order_id) DO NOTHING;

UPDATE public.escrow e
SET
  status = 'released'::public.escrow_status_enum,
  released_at = COALESCE(e.released_at, now()),
  release_reason = COALESCE(e.release_reason, 'order_completed')
FROM public.orders o
WHERE o.order_id = e.order_id
  AND o.order_status = 'completed'::public.order_status_enum
  AND e.status IN (
    'held'::public.escrow_status_enum,
    'disputed'::public.escrow_status_enum
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.delivery_disputes d
    WHERE d.order_id = e.order_id
      AND d.status = 'open'::public.delivery_dispute_status_enum
  );
