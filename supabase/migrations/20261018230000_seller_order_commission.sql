-- 5% ThriftLine seller commission per seller order (product subtotal only).
-- One commission calculation per orders row (one shop). Shipping and the
-- buyer 2% PayMongo platform_fee stay separate. Revenue is recognized when
-- escrow is released (completed order), reversed when escrow is refunded.
-- Idempotent. Do not edit earlier migrations.

-- ===========================================================================
-- 1. Schema
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'seller_commission_status_enum'
  ) THEN
    CREATE TYPE public.seller_commission_status_enum AS ENUM (
      'pending',
      'earned',
      'reversed',
      'void'
    );
  END IF;
END
$$;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_commission_rate numeric(8, 4),
  ADD COLUMN IF NOT EXISTS seller_commission_base numeric(12, 2),
  ADD COLUMN IF NOT EXISTS seller_commission_amount numeric(12, 2),
  ADD COLUMN IF NOT EXISTS seller_commission_status public.seller_commission_status_enum
    NOT NULL DEFAULT 'pending'::public.seller_commission_status_enum,
  ADD COLUMN IF NOT EXISTS seller_commission_recognized_at timestamptz,
  ADD COLUMN IF NOT EXISTS seller_commission_reversed_at timestamptz;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_seller_commission_nonneg_chk;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_seller_commission_nonneg_chk
  CHECK (
    seller_commission_amount IS NULL
    OR seller_commission_amount >= 0
  );

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_seller_commission_rate_chk;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_seller_commission_rate_chk
  CHECK (
    seller_commission_rate IS NULL
    OR (seller_commission_rate >= 0 AND seller_commission_rate <= 1)
  );

CREATE INDEX IF NOT EXISTS orders_seller_commission_earned_idx
  ON public.orders (seller_commission_recognized_at)
  WHERE seller_commission_status = 'earned'::public.seller_commission_status_enum;

CREATE INDEX IF NOT EXISTS orders_seller_commission_reversed_idx
  ON public.orders (seller_commission_reversed_at)
  WHERE seller_commission_status = 'reversed'::public.seller_commission_status_enum;

COMMENT ON COLUMN public.orders.seller_commission_rate IS
  'Persisted ThriftLine seller commission rate for this seller order (currently 0.05).';
COMMENT ON COLUMN public.orders.seller_commission_base IS
  'Commissionable product subtotal for this seller order. Excludes shipping and buyer platform_fee.';
COMMENT ON COLUMN public.orders.seller_commission_amount IS
  'Rounded 5% of seller_commission_base for this seller order (not per item).';
COMMENT ON COLUMN public.orders.seller_commission_status IS
  'pending until escrow release; earned on completed/released; reversed on refund; void if never paid.';

-- ===========================================================================
-- 2. Calculation + recognition (backend only)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.seller_commission_amount(
  p_base numeric,
  p_rate numeric DEFAULT 0.05
)
RETURNS numeric(12, 2)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT ROUND(
    GREATEST(COALESCE(p_base, 0), 0) * COALESCE(p_rate, 0.05),
    2
  )::numeric(12, 2);
$$;

REVOKE ALL ON FUNCTION public.seller_commission_amount(numeric, numeric)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.recognize_order_seller_commission(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.orders
  SET seller_commission_status = 'earned'::public.seller_commission_status_enum,
      seller_commission_recognized_at = COALESCE(seller_commission_recognized_at, now()),
      seller_commission_reversed_at = NULL
  WHERE order_id = p_order_id
    AND seller_commission_status = 'pending'::public.seller_commission_status_enum;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_order_seller_commission(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.orders
  SET seller_commission_status = 'reversed'::public.seller_commission_status_enum,
      seller_commission_reversed_at = COALESCE(seller_commission_reversed_at, now())
  WHERE order_id = p_order_id
    AND seller_commission_status IN (
      'pending'::public.seller_commission_status_enum,
      'earned'::public.seller_commission_status_enum
    );
END;
$$;

REVOKE ALL ON FUNCTION public.recognize_order_seller_commission(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reverse_order_seller_commission(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_orders_apply_seller_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rate numeric(8, 4) := 0.05;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.seller_commission_rate := v_rate;
    NEW.seller_commission_base := ROUND(COALESCE(NEW.subtotal, 0), 2);
    NEW.seller_commission_amount := public.seller_commission_amount(
      NEW.seller_commission_base,
      NEW.seller_commission_rate
    );
    NEW.seller_commission_status := COALESCE(
      NEW.seller_commission_status,
      'pending'::public.seller_commission_status_enum
    );
    RETURN NEW;
  END IF;

  IF OLD.seller_commission_status IN (
       'earned'::public.seller_commission_status_enum,
       'reversed'::public.seller_commission_status_enum
     ) THEN
    NEW.seller_commission_rate := OLD.seller_commission_rate;
    NEW.seller_commission_base := OLD.seller_commission_base;
    NEW.seller_commission_amount := OLD.seller_commission_amount;
  ELSE
    NEW.seller_commission_rate := COALESCE(OLD.seller_commission_rate, v_rate);
    NEW.seller_commission_base := ROUND(COALESCE(NEW.subtotal, 0), 2);
    NEW.seller_commission_amount := public.seller_commission_amount(
      NEW.seller_commission_base,
      NEW.seller_commission_rate
    );
  END IF;

  IF NEW.order_status = 'cancelled'::public.order_status_enum
     AND OLD.order_status IS DISTINCT FROM 'cancelled'::public.order_status_enum
     AND NEW.seller_commission_status = 'pending'::public.seller_commission_status_enum
     AND NOT EXISTS (
       SELECT 1
       FROM public.payments p
       WHERE p.order_id = NEW.order_id
         AND p.payment_status = 'paid'::public.payment_status_enum
     )
  THEN
    NEW.seller_commission_status := 'void'::public.seller_commission_status_enum;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_apply_seller_commission ON public.orders;
CREATE TRIGGER trg_orders_apply_seller_commission
BEFORE INSERT OR UPDATE OF subtotal, order_status, seller_commission_status
ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_apply_seller_commission();

CREATE OR REPLACE FUNCTION public.trg_escrow_sync_seller_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'released'::public.escrow_status_enum
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status)
  THEN
    PERFORM public.recognize_order_seller_commission(NEW.order_id);
  ELSIF NEW.status = 'refunded'::public.escrow_status_enum
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status)
  THEN
    PERFORM public.reverse_order_seller_commission(NEW.order_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_escrow_sync_seller_commission ON public.escrow;
CREATE TRIGGER trg_escrow_sync_seller_commission
AFTER INSERT OR UPDATE OF status ON public.escrow
FOR EACH ROW
EXECUTE FUNCTION public.trg_escrow_sync_seller_commission();

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
  v_commission_centavos integer;
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

  v_commission_centavos := ROUND(
    COALESCE(
      v_order.seller_commission_amount,
      public.seller_commission_amount(v_order.subtotal, 0.05)
    ) * 100
  )::integer;

  v_seller_centavos := GREATEST(
    0,
    v_payment.amount_centavos
      - ROUND(COALESCE(v_order.platform_fee, 0) * 100)::integer
      - v_commission_centavos
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
    SELECT escrow_id, status INTO v_escrow_id, v_status
    FROM public.escrow
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF v_status IN (
         'held'::public.escrow_status_enum,
         'disputed'::public.escrow_status_enum
       )
    THEN
      UPDATE public.escrow
      SET seller_amount_centavos = v_seller_centavos
      WHERE escrow_id = v_escrow_id
        AND status IN (
          'held'::public.escrow_status_enum,
          'disputed'::public.escrow_status_enum
        )
        AND seller_amount_centavos IS DISTINCT FROM v_seller_centavos;
    END IF;
  END IF;

  RETURN v_escrow_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_dashboard_commission_net(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    COALESCE((
      SELECT sum(o.seller_commission_amount)
      FROM public.orders o
      WHERE o.seller_commission_status = 'earned'::public.seller_commission_status_enum
        AND o.seller_commission_recognized_at IS NOT NULL
        AND (p_from IS NULL OR o.seller_commission_recognized_at >= p_from)
        AND (p_to IS NULL OR o.seller_commission_recognized_at < p_to)
    ), 0)
    -
    COALESCE((
      SELECT sum(o.seller_commission_amount)
      FROM public.orders o
      WHERE o.seller_commission_status = 'reversed'::public.seller_commission_status_enum
        AND o.seller_commission_recognized_at IS NOT NULL
        AND o.seller_commission_reversed_at IS NOT NULL
        AND (p_from IS NULL OR o.seller_commission_reversed_at >= p_from)
        AND (p_to IS NULL OR o.seller_commission_reversed_at < p_to)
    ), 0);
$$;

CREATE OR REPLACE FUNCTION public._admin_dashboard_commission_events(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS TABLE (occurred_at timestamptz, amount numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT o.seller_commission_recognized_at, o.seller_commission_amount
  FROM public.orders o
  WHERE o.seller_commission_status = 'earned'::public.seller_commission_status_enum
    AND o.seller_commission_recognized_at IS NOT NULL
    AND (p_from IS NULL OR o.seller_commission_recognized_at >= p_from)
    AND (p_to IS NULL OR o.seller_commission_recognized_at < p_to)
  UNION ALL
  SELECT o.seller_commission_reversed_at, -o.seller_commission_amount
  FROM public.orders o
  WHERE o.seller_commission_status = 'reversed'::public.seller_commission_status_enum
    AND o.seller_commission_recognized_at IS NOT NULL
    AND o.seller_commission_reversed_at IS NOT NULL
    AND (p_from IS NULL OR o.seller_commission_reversed_at >= p_from)
    AND (p_to IS NULL OR o.seller_commission_reversed_at < p_to);
$$;

REVOKE ALL ON FUNCTION public._admin_dashboard_commission_net(timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_commission_events(timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;

-- Earliest paid timestamp for one order inside an optional window.
-- Not granted to clients. Used only by admin_dashboard_snapshot.
CREATE OR REPLACE FUNCTION public._admin_dashboard_paid_at(
  p_order_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT min(p.updated_at)
  FROM public.payments p
  WHERE p.order_id = p_order_id
    AND p.payment_status = 'paid'::public.payment_status_enum
    AND (p_from IS NULL OR p.updated_at >= p_from)
    AND (p_to IS NULL OR p.updated_at < p_to);
$$;

-- True when the order has a paid payment in the window and escrow is not refunded.
CREATE OR REPLACE FUNCTION public._admin_dashboard_order_paid(
  p_order_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public._admin_dashboard_paid_at(p_order_id, p_from, p_to) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.escrow e
      WHERE e.order_id = p_order_id
        AND e.status = 'refunded'::public.escrow_status_enum
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_dashboard_snapshot(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_compare_from timestamptz DEFAULT NULL,
  p_compare_to timestamptz DEFAULT NULL,
  p_bucket text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_to timestamptz;
  v_bucket text;
  v_bucket_in text;
  v_compare boolean := false;
  v_user_start timestamptz;
  v_pay_start timestamptz;
  v_history_start timestamptz;
  v_series_from timestamptz;
  v_series_to timestamptz;
  v_origin timestamp;
  v_end_bucket timestamp;
  v_compare_origin timestamp;
  v_step interval;
  v_span_days numeric;
  v_new_users integer := 0;
  v_new_users_prev integer := 0;
  v_completed integer := 0;
  v_completed_prev integer := 0;
  v_paid_orders integer := 0;
  v_paid_orders_prev integer := 0;
  v_revenue numeric := 0;
  v_revenue_prev numeric := 0;
  v_gross numeric := 0;
  v_listings integer := 0;
  v_applications integer := 0;
  v_auction_orders integer := 0;
  v_awaiting integer := 0;
  v_pending_verifications integer := 0;
  v_open_community integer := 0;
  v_open_order integer := 0;
  v_open_looking_for integer := 0;
  v_bidding integer := 0;
  v_payment_review integer := 0;
  v_total_users integer := 0;
  v_period_orders integer := 0;
  v_period_reports integer := 0;
  v_order_categories text[] := ARRAY[
    'seller_not_processing_order',
    'counterfeit_received',
    'item_not_as_described',
    'undisclosed_damage',
    'buyer_delivery_pin_issue',
    'fake_product',
    'counterfeit_item',
    'failure_to_ship'
  ];
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can view the dashboard.'
    );
  END IF;

  v_to := coalesce(p_to, now());
  IF p_from IS NOT NULL AND v_to <= p_from THEN
    v_to := p_from + interval '1 second';
  END IF;

  v_compare := p_from IS NOT NULL
    AND p_compare_from IS NOT NULL
    AND p_compare_to IS NOT NULL
    AND p_compare_to > p_compare_from
    AND (
      EXISTS (SELECT 1 FROM public.users u WHERE u.created_at < p_from)
      OR EXISTS (
        SELECT 1 FROM public.payments p
        WHERE p.payment_status = 'paid'::public.payment_status_enum
          AND p.updated_at < p_from
      )
    );

  SELECT min(u.created_at) INTO v_user_start FROM public.users u;
  SELECT min(p.updated_at) INTO v_pay_start
  FROM public.payments p
  WHERE p.payment_status = 'paid'::public.payment_status_enum;

  v_history_start := CASE
    WHEN v_user_start IS NULL THEN v_pay_start
    WHEN v_pay_start IS NULL THEN v_user_start
    WHEN v_user_start < v_pay_start THEN v_user_start
    ELSE v_pay_start
  END;

  v_bucket_in := lower(btrim(coalesce(p_bucket, '')));
  IF v_bucket_in = 'auto' THEN
    IF v_history_start IS NOT NULL
       AND v_history_start < v_to - interval '36 months' THEN
      v_bucket := 'year';
    ELSE
      v_bucket := 'month';
    END IF;
  ELSIF v_bucket_in IN ('hour', 'day', 'month', 'year') THEN
    v_bucket := v_bucket_in;
  ELSIF p_from IS NULL THEN
    v_bucket := 'month';
  ELSE
    v_span_days := EXTRACT(EPOCH FROM (v_to - p_from)) / 86400.0;
    IF v_span_days <= 1.01 THEN
      v_bucket := 'hour';
    ELSIF v_span_days > 62 THEN
      v_bucket := 'month';
    ELSE
      v_bucket := 'day';
    END IF;
  END IF;

  v_step := CASE v_bucket
    WHEN 'hour' THEN interval '1 hour'
    WHEN 'day' THEN interval '1 day'
    WHEN 'month' THEN interval '1 month'
    ELSE interval '1 year'
  END;

  v_series_to := least(v_to, now());
  IF p_from IS NULL THEN
    v_series_from := v_history_start;
  ELSE
    v_series_from := p_from;
  END IF;

  IF v_series_from IS NOT NULL AND v_series_to > v_series_from THEN
    v_origin := date_trunc(v_bucket, timezone('Asia/Manila', v_series_from));
    v_end_bucket := date_trunc(
      v_bucket,
      timezone('Asia/Manila', v_series_to - interval '1 millisecond')
    );
    IF v_end_bucket < v_origin THEN
      v_end_bucket := v_origin;
    END IF;
    IF v_compare THEN
      v_compare_origin := date_trunc(
        v_bucket,
        timezone('Asia/Manila', p_compare_from)
      );
    END IF;
  END IF;

  SELECT count(*)::int INTO v_new_users
  FROM public.users u
  WHERE (p_from IS NULL OR u.created_at >= p_from)
    AND u.created_at < v_to;

  SELECT count(*)::int INTO v_completed
  FROM public.orders o
  JOIN public.shipments s ON s.order_id = o.order_id
  WHERE o.order_status = 'completed'::public.order_status_enum
    AND s.completed_at IS NOT NULL
    AND (p_from IS NULL OR s.completed_at >= p_from)
    AND s.completed_at < v_to;

  SELECT
    count(*)::int,
    coalesce(sum(o.subtotal + o.shipping_fee), 0)
  INTO v_paid_orders, v_gross
  FROM public.orders o
  WHERE public._admin_dashboard_order_paid(o.order_id, p_from, v_to);

  v_revenue := public._admin_dashboard_commission_net(p_from, v_to);

  SELECT count(*)::int INTO v_listings
  FROM public.products p
  WHERE p.status IS DISTINCT FROM 'removed'::public.product_status_enum
    AND (p_from IS NULL OR p.created_at >= p_from)
    AND p.created_at < v_to;

  SELECT count(*)::int INTO v_applications
  FROM public.user_verifications v
  WHERE (p_from IS NULL OR v.submitted_at >= p_from)
    AND v.submitted_at < v_to;

  SELECT count(*)::int INTO v_auction_orders
  FROM public.orders o
  WHERE o.order_type = 'auction'::public.order_type_enum
    AND public._admin_dashboard_order_paid(o.order_id, p_from, v_to);

  SELECT count(*)::int INTO v_awaiting
  FROM public.orders o
  WHERE o.order_status NOT IN (
      'cancelled'::public.order_status_enum,
      'completed'::public.order_status_enum
    )
    AND public._admin_dashboard_order_paid(o.order_id, NULL, now() + interval '1 second')
    AND NOT EXISTS (
      SELECT 1 FROM public.shipments s
      WHERE s.order_id = o.order_id
        AND s.completed_at IS NOT NULL
    );

  SELECT count(*)::int INTO v_pending_verifications
  FROM public.user_verifications v
  WHERE v.verification_status = 'pending'::public.verification_status_enum;

  SELECT count(*)::int INTO v_open_community
  FROM public.reports r
  WHERE r.status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    )
    AND r.order_id IS NULL
    AND NOT (r.category = ANY (v_order_categories));

  SELECT count(*)::int INTO v_open_order
  FROM public.reports r
  WHERE r.status IN (
      'under_review'::public.report_status_enum,
      'needs_more_evidence'::public.report_status_enum
    )
    AND (
      r.order_id IS NOT NULL
      OR r.category = ANY (v_order_categories)
    );

  SELECT count(*)::int INTO v_open_looking_for
  FROM public.looking_for_reports r
  WHERE r.status IN (
    'under_review'::public.report_status_enum,
    'needs_more_evidence'::public.report_status_enum
  );

  SELECT count(*)::int INTO v_bidding
  FROM public.auction_bidding_sanctions s
  WHERE s.permanently_disabled_at IS NOT NULL
     OR (s.restricted_until IS NOT NULL AND s.restricted_until > now());

  SELECT count(*)::int INTO v_payment_review
  FROM public.orders o
  WHERE o.order_status = 'cancelled'::public.order_status_enum
    AND EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.order_id = o.order_id
        AND p.payment_status = 'paid'::public.payment_status_enum
    );

  SELECT count(*)::int INTO v_total_users FROM public.users u;

  SELECT count(*)::int INTO v_period_orders
  FROM public.orders o
  WHERE (p_from IS NULL OR o.created_at >= p_from)
    AND o.created_at < v_to;

  SELECT count(*)::int INTO v_period_reports
  FROM public.reports r
  WHERE (p_from IS NULL OR r.created_at >= p_from)
    AND r.created_at < v_to;

  IF v_compare THEN
    SELECT count(*)::int INTO v_new_users_prev
    FROM public.users u
    WHERE u.created_at >= p_compare_from
      AND u.created_at < p_compare_to;

    SELECT count(*)::int INTO v_completed_prev
    FROM public.orders o
    JOIN public.shipments s ON s.order_id = o.order_id
    WHERE o.order_status = 'completed'::public.order_status_enum
      AND s.completed_at IS NOT NULL
      AND s.completed_at >= p_compare_from
      AND s.completed_at < p_compare_to;

    SELECT count(*)::int
    INTO v_paid_orders_prev
    FROM public.orders o
    WHERE public._admin_dashboard_order_paid(o.order_id, p_compare_from, p_compare_to);

    v_revenue_prev := public._admin_dashboard_commission_net(p_compare_from, p_compare_to);
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'schema', 2,
    'generated_at', now(),
    'bucket', v_bucket,
    'comparison_available', v_compare,
    'kpis', jsonb_build_object(
      'new_users', v_new_users,
      'new_users_previous', CASE WHEN v_compare THEN to_jsonb(v_new_users_prev) ELSE NULL END,
      'completed_orders', v_completed,
      'completed_orders_previous', CASE WHEN v_compare THEN to_jsonb(v_completed_prev) ELSE NULL END,
      'platform_revenue', v_revenue,
      'platform_revenue_previous', CASE WHEN v_compare THEN to_jsonb(v_revenue_prev) ELSE NULL END,
      'paid_orders', v_paid_orders,
      'paid_orders_previous', CASE WHEN v_compare THEN to_jsonb(v_paid_orders_prev) ELSE NULL END
    ),
    'activity', jsonb_build_object(
      'new_listings', v_listings,
      'seller_applications', v_applications,
      'paid_auction_orders', v_auction_orders,
      'orders_awaiting_fulfillment', v_awaiting
    ),
    'attention', jsonb_build_object(
      'pending_verifications', v_pending_verifications,
      'open_community_disputes', v_open_community,
      'open_order_disputes', v_open_order,
      'open_looking_for_disputes', v_open_looking_for,
      'active_bidding_restrictions', v_bidding,
      'payment_reviews', v_payment_review
    ),
    'revenue_series', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'at', g.bucket_at,
          'current', COALESCE(cur.amount, 0),
          'previous', CASE
            WHEN v_compare THEN to_jsonb(COALESCE(prev.amount, 0))
            ELSE NULL
          END
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.bucket_local,
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          CASE
            WHEN v_compare THEN v_compare_origin + ((s.ord - 1) * v_step)
            ELSE NULL
          END AS prev_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', ev.occurred_at)) AS bucket_local,
          coalesce(sum(ev.amount), 0) AS amount
        FROM public._admin_dashboard_commission_events(p_from, v_to) ev
        WHERE ev.occurred_at IS NOT NULL
        GROUP BY 1
      ) cur ON cur.bucket_local = g.bucket_local
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', ev.occurred_at)) AS bucket_local,
          coalesce(sum(ev.amount), 0) AS amount
        FROM public._admin_dashboard_commission_events(p_compare_from, p_compare_to) ev
        WHERE v_compare
          AND ev.occurred_at IS NOT NULL
        GROUP BY 1
      ) prev ON prev.bucket_local = g.prev_local
    ), '[]'::jsonb),
    'recent_activity', COALESCE((
      SELECT jsonb_agg(item ORDER BY occurred_at DESC)
      FROM (
        SELECT item, occurred_at
        FROM (
          SELECT
            v.submitted_at AS occurred_at,
            jsonb_build_object(
              'kind', 'verification_submitted',
              'occurred_at', v.submitted_at,
              'title', 'Seller verification submitted',
              'detail', coalesce(nullif(btrim(v.shop_name), ''), 'New shop'),
              'actor', 'member',
              'target_type', 'verification',
              'target_id', v.verification_id::text
            ) AS item
          FROM public.user_verifications v

          UNION ALL

          SELECT
            r.created_at,
            jsonb_build_object(
              'kind', CASE
                WHEN r.order_id IS NOT NULL OR r.category = ANY (v_order_categories)
                  THEN 'order_report_submitted'
                ELSE 'community_report_submitted'
              END,
              'occurred_at', r.created_at,
              'title', CASE
                WHEN r.order_id IS NOT NULL OR r.category = ANY (v_order_categories)
                  THEN 'Order dispute submitted'
                ELSE 'Community dispute submitted'
              END,
              'detail', replace(r.category, '_', ' '),
              'actor', 'member',
              'target_type', 'report',
              'target_id', r.report_id::text
            )
          FROM public.reports r

          UNION ALL

          SELECT
            r.created_at,
            jsonb_build_object(
              'kind', 'looking_for_report_submitted',
              'occurred_at', r.created_at,
              'title', 'Looking For dispute submitted',
              'detail', replace(r.reason, '_', ' '),
              'actor', 'member',
              'target_type', 'looking_for_report',
              'target_id', r.report_id::text
            )
          FROM public.looking_for_reports r

          UNION ALL

          SELECT
            l.created_at,
            jsonb_build_object(
              'kind', l.event_type,
              'occurred_at', l.created_at,
              'title', l.summary,
              'detail', '',
              'actor', 'admin',
              'target_type', coalesce(l.target_type, ''),
              'target_id', coalesce(l.target_id, '')
            )
          FROM public.admin_audit_logs l
          WHERE l.category <> 'authentication'
            AND l.event_type IN (
              'seller_verification_approved',
              'seller_verification_rejected',
              'report_decided',
              'order_report_closed',
              'order_report_evidence_requested',
              'looking_for_report_decided',
              'delivery_dispute_closed'
            )

          UNION ALL

          SELECT
            v.created_at,
            jsonb_build_object(
              'kind', 'bidding_violation',
              'occurred_at', v.created_at,
              'title', 'Bidding violation recorded',
              'detail', 'Auction winner non-payment',
              'actor', 'system',
              'target_type', 'order',
              'target_id', v.order_id::text
            )
          FROM public.auction_bidding_violations v
        ) events
        ORDER BY occurred_at DESC
        LIMIT 12
      ) recent
    ), '[]'::jsonb),
    'counts', jsonb_build_object(
      'total_users', v_total_users,
      'period_users', v_new_users,
      'pending_verifications', v_pending_verifications,
      'period_verifications', v_applications,
      'open_reports', v_open_community + v_open_order,
      'period_reports', v_period_reports,
      'period_orders', v_period_orders,
      'open_disputes', v_open_community + v_open_order + v_open_looking_for,
      'gross_marketplace_sales', v_gross,
      'platform_revenue', v_revenue
    ),
    'registrations', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', u.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.users u
        WHERE (p_from IS NULL OR u.created_at >= p_from)
          AND u.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'orders_by_day', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', o.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.orders o
        WHERE (p_from IS NULL OR o.created_at >= p_from)
          AND o.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'orders_by_status', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      )
      FROM (
        SELECT o.order_status::text AS status, count(*)::int AS cnt
        FROM public.orders o
        WHERE (p_from IS NULL OR o.created_at >= p_from)
          AND o.created_at < v_to
        GROUP BY 1
      ) s
    ), '[]'::jsonb),
    'reports_by_day', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'count', COALESCE(c.cnt, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', r.created_at)) AS bucket_local,
          count(*)::int AS cnt
        FROM public.reports r
        WHERE (p_from IS NULL OR r.created_at >= p_from)
          AND r.created_at < v_to
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
    ), '[]'::jsonb),
    'reports_by_status', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('status', s.status, 'count', s.cnt)
        ORDER BY s.cnt DESC, s.status
      )
      FROM (
        SELECT r.status::text AS status, count(*)::int AS cnt
        FROM public.reports r
        WHERE (p_from IS NULL OR r.created_at >= p_from)
          AND r.created_at < v_to
        GROUP BY 1
      ) s
    ), '[]'::jsonb),
    'sales_revenue_series', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'day', g.bucket_at,
          'gross', COALESCE(c.gross, 0),
          'platform_revenue', COALESCE(r.platform, 0)
        )
        ORDER BY g.ord
      )
      FROM (
        SELECT
          s.ord,
          (s.bucket_local AT TIME ZONE 'Asia/Manila') AS bucket_at,
          s.bucket_local
        FROM generate_series(v_origin, v_end_bucket, v_step) WITH ORDINALITY AS s(bucket_local, ord)
        WHERE v_origin IS NOT NULL
      ) g
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', paid.paid_at)) AS bucket_local,
          sum(o.subtotal + o.shipping_fee) AS gross
        FROM public.orders o
        JOIN LATERAL (
          SELECT public._admin_dashboard_paid_at(o.order_id, p_from, v_to) AS paid_at
        ) paid ON paid.paid_at IS NOT NULL
        WHERE public._admin_dashboard_order_paid(o.order_id, p_from, v_to)
        GROUP BY 1
      ) c ON c.bucket_local = g.bucket_local
      LEFT JOIN (
        SELECT
          date_trunc(v_bucket, timezone('Asia/Manila', ev.occurred_at)) AS bucket_local,
          coalesce(sum(ev.amount), 0) AS platform
        FROM public._admin_dashboard_commission_events(p_from, v_to) ev
        GROUP BY 1
      ) r ON r.bucket_local = g.bucket_local
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text) IS
  'Admin dashboard snapshot. Platform revenue is earned 5% seller-order commissions (recognized on escrow release), net of reversals. Buyer platform_fee is PayMongo coverage and is not included.';

REVOKE ALL ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_snapshot(timestamptz, timestamptz, timestamptz, timestamptz, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public._admin_dashboard_paid_at(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_order_paid(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_paid_at(uuid, timestamptz, timestamptz)
  TO CURRENT_USER;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_order_paid(uuid, timestamptz, timestamptz)
  TO CURRENT_USER;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_commission_net(timestamptz, timestamptz)
  TO CURRENT_USER;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_commission_events(timestamptz, timestamptz)
  TO CURRENT_USER;

-- ===========================================================================
-- 3. Seller transaction history + earnings activity
-- ===========================================================================

DROP FUNCTION IF EXISTS public.list_my_seller_payment_transactions();

CREATE FUNCTION public.list_my_seller_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  paid_at timestamptz,
  amount_centavos integer,
  seller_amount_centavos integer,
  subtotal_centavos integer,
  shipping_fee_centavos integer,
  commission_rate numeric,
  commission_amount_centavos integer,
  commission_status text,
  order_status text,
  payment_status text,
  payment_method text,
  paymongo_channel text,
  transaction_reference text,
  refunded_at timestamptz,
  refund_amount_centavos integer,
  refund_provider_status text,
  escrow_id uuid,
  escrow_status text,
  refund_state text,
  refund_completed_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.payment_id,
    o.order_id,
    o.order_number::text,
    COALESCE(
      (
        SELECT oi.title::text
        FROM public.order_items oi
        WHERE oi.order_id = o.order_id
        ORDER BY oi.created_at
        LIMIT 1
      ),
      'Order'::text
    ) AS product_title,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    COALESCE(e.seller_amount_centavos, 0) AS seller_amount_centavos,
    ROUND(COALESCE(o.subtotal, 0) * 100)::integer AS subtotal_centavos,
    ROUND(COALESCE(o.shipping_fee, 0) * 100)::integer AS shipping_fee_centavos,
    COALESCE(o.seller_commission_rate, 0.05) AS commission_rate,
    ROUND(COALESCE(o.seller_commission_amount, 0) * 100)::integer AS commission_amount_centavos,
    o.seller_commission_status::text,
    o.order_status::text,
    p.payment_status::text,
    p.payment_method::text,
    p.paymongo_channel::text,
    p.transaction_reference::text,
    e.refunded_at,
    CASE
      WHEN e.status = 'refunded'::public.escrow_status_enum
        THEN COALESCE(e.seller_amount_centavos, 0)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text,
    e.escrow_id,
    e.status::text AS escrow_status,
    e.refund_state::text,
    e.refund_completed_at
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
  WHERE o.seller_id = v_uid
    AND p.payment_status IN (
      'paid'::public.payment_status_enum,
      'refunded'::public.payment_status_enum
    )
  ORDER BY COALESCE(e.refunded_at, public.order_paid_at(o.order_id), p.updated_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_seller_payment_transactions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_seller_payment_transactions()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.list_my_seller_payment_transactions() IS
  'Paid and refunded seller orders with per-order 5% ThriftLine commission breakdown.';

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
  v_requested integer := 0;
  v_paid integer := 0;
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

  SELECT COALESCE(SUM(amount_centavos) FILTER (
           WHERE status = 'requested'::public.seller_payout_status_enum
         ), 0),
         COALESCE(SUM(amount_centavos) FILTER (
           WHERE status = 'paid'::public.seller_payout_status_enum
         ), 0)
  INTO v_requested, v_paid
  FROM public.seller_payouts
  WHERE seller_id = v_uid;

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
      'subtotal_centavos', ROUND(COALESCE(o.subtotal, 0) * 100)::integer,
      'shipping_fee_centavos', ROUND(COALESCE(o.shipping_fee, 0) * 100)::integer,
      'commission_rate', COALESCE(o.seller_commission_rate, 0.05),
      'commission_amount_centavos', ROUND(COALESCE(o.seller_commission_amount, 0) * 100)::integer,
      'commission_status', o.seller_commission_status::text,
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
      'gcash_account_name', p.gcash_account_name,
      'gcash_mobile_number', p.gcash_mobile_number,
      'gcash_reference', p.gcash_reference,
      'transferred_amount_centavos', p.transferred_amount_centavos,
      'transferred_at', p.transferred_at,
      'rejection_reason', p.rejection_reason,
      'cancelled_at', p.cancelled_at,
      'processed_at', p.processed_at,
      'sort_at', p.requested_at
    ) AS item,
    p.requested_at AS sort_at
    FROM public.seller_payouts p
    WHERE p.seller_id = v_uid
    ORDER BY p.requested_at DESC
    LIMIT 20
  ) listed;

  RETURN jsonb_build_object(
    'success', true,
    'held_centavos', v_held,
    'released_centavos', v_released,
    'refunded_centavos', v_refunded,
    'payout_requested_centavos', v_requested,
    'payout_paid_centavos', v_paid,
    'available_centavos', GREATEST(0, v_released - v_requested - v_paid),
    'listing_count', v_listings,
    'activity', v_activity,
    'payouts', v_payouts
  );
END;
$$;

REVOKE ALL ON FUNCTION public.seller_earnings_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_earnings_snapshot() TO authenticated;

-- ===========================================================================
-- 4. Marketplace payments report: net revenue = earned commissions
-- ===========================================================================

CREATE OR REPLACE FUNCTION public._admin_report_payments_bundle(
  p_from timestamptz,
  p_to timestamptz,
  p_cf timestamptz,
  p_ct timestamptz,
  p_filters jsonb,
  p_limit integer,
  p_offset integer
)
RETURNS TABLE (
  summary jsonb,
  comparison jsonb,
  breakdowns jsonb,
  details jsonb,
  limitations jsonb,
  detail_total bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ps text := nullif(trim(p_filters->>'payment_status'), '');
  v_total bigint;
  v_paid_count bigint;
  v_gpv numeric;
  v_gov numeric;
  v_fees_collected numeric;
  v_fees_assessed numeric;
  v_pending numeric;
  v_refund_amt numeric;
  v_failed bigint;
  v_net numeric;
BEGIN
  SELECT count(*), coalesce(sum(p.amount_centavos), 0) / 100.0
  INTO v_paid_count, v_gpv
  FROM public.payments p
  WHERE p.payment_status = 'paid'::public.payment_status_enum
    AND p.updated_at >= p_from AND p.updated_at < p_to;

  SELECT coalesce(sum(o.subtotal + o.shipping_fee), 0),
         coalesce(sum(o.platform_fee), 0)
  INTO v_gov, v_fees_collected
  FROM public.orders o
  WHERE EXISTS (
    SELECT 1 FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
      AND p.updated_at >= p_from AND p.updated_at < p_to
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.escrow e
    WHERE e.order_id = o.order_id AND e.status = 'refunded'::public.escrow_status_enum
  );

  SELECT coalesce(sum(o.platform_fee), 0) INTO v_fees_assessed
  FROM public.orders o
  WHERE o.created_at >= p_from AND o.created_at < p_to;

  SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 INTO v_pending
  FROM public.escrow e
  WHERE e.status IN ('held'::public.escrow_status_enum, 'disputed'::public.escrow_status_enum);

  SELECT coalesce(sum(e.amount_centavos), 0) / 100.0 INTO v_refund_amt
  FROM public.escrow e
  WHERE e.status = 'refunded'::public.escrow_status_enum
    AND e.refunded_at >= p_from AND e.refunded_at < p_to;

  SELECT count(*) INTO v_failed
  FROM public.payments p
  WHERE p.payment_status = 'failed'::public.payment_status_enum
    AND p.updated_at >= p_from AND p.updated_at < p_to;

  v_net := public._admin_dashboard_commission_net(p_from, p_to);

  summary := jsonb_build_array(
    public._admin_report_metric('successful_payments', 'Successful order payments', v_paid_count),
    public._admin_report_metric('gross_payment_volume', 'Gross payment volume', v_gpv, 'money'),
    public._admin_report_metric('gross_order_value', 'Gross order value', v_gov, 'money'),
    public._admin_report_metric('platform_fees_collected', 'Buyer PayMongo fees collected', v_fees_collected, 'money'),
    public._admin_report_metric('platform_fees_assessed', 'Buyer PayMongo fees assessed (orders created)', v_fees_assessed, 'money'),
    public._admin_report_metric('seller_allocations', 'Seller allocations (held_at in period)',
      (SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 FROM public.escrow e
       WHERE e.held_at >= p_from AND e.held_at < p_to), 'money'),
    public._admin_report_metric('released_earnings', 'Released seller earnings',
      (SELECT coalesce(sum(e.seller_amount_centavos), 0) / 100.0 FROM public.escrow e
       WHERE e.status = 'released'::public.escrow_status_enum
         AND e.released_at >= p_from AND e.released_at < p_to), 'money'),
    public._admin_report_metric('pending_escrow', 'Pending escrow (snapshot)', v_pending, 'money', true),
    public._admin_report_metric('refunds', 'Confirmed refunds', v_refund_amt, 'money'),
    public._admin_report_metric('failed_payments', 'Failed payments', v_failed),
    public._admin_report_metric('net_platform_revenue', 'ThriftLine commission (5% of product subtotal, earned)', v_net, 'money')
  );

  comparison := '[]'::jsonb;
  breakdowns := jsonb_build_array(
    jsonb_build_object(
      'title', 'Payment status (updated in period)',
      'columns', jsonb_build_array('Status', 'Count'),
      'rows', (
        SELECT coalesce(jsonb_agg(jsonb_build_array(p.payment_status::text, p.cnt)), '[]'::jsonb)
        FROM (
          SELECT payment_status, count(*) AS cnt
          FROM public.payments
          WHERE updated_at >= p_from AND updated_at < p_to
          GROUP BY 1
        ) p
      )
    )
  );

  limitations := jsonb_build_array(
    'Successful payments dated by payments.updated_at (no paid_at column).',
    'Gross payment volume sums all paid payment rows; multi-shop checkout has one row per seller.',
    'Net platform revenue is earned 5% seller-order commissions (recognized on escrow release), not buyer PayMongo fees.',
    'Buyer platform_fee remains a separate PayMongo coverage charge and is not ThriftLine commission.',
    'GCash disbursements are not tracked beyond payout requests.',
    'Expired PayMongo sessions are stored as failed payments.'
  );

  SELECT count(*) INTO v_total
  FROM public.payments p
  WHERE p.updated_at >= p_from AND p.updated_at < p_to
    AND (v_ps IS NULL OR p.payment_status::text = v_ps);

  details := jsonb_build_object(
    'columns', jsonb_build_array('Updated', 'Status', 'Amount', 'Order'),
    'rows', coalesce((
      SELECT jsonb_agg(src.row_data)
      FROM (
        SELECT jsonb_build_array(
          public._admin_report_manila_datetime(p.updated_at),
          p.payment_status::text,
          round(p.amount_centavos / 100.0, 2),
          left(p.order_id::text, 8)
        ) AS row_data
        FROM public.payments p
        WHERE p.updated_at >= p_from AND p.updated_at < p_to
          AND (v_ps IS NULL OR p.payment_status::text = v_ps)
        ORDER BY p.updated_at DESC
        LIMIT p_limit OFFSET p_offset
      ) src
    ), '[]'::jsonb),
    'total', v_total,
    'truncated', v_total > (p_offset + p_limit)
  );

  detail_total := v_total;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- 5. Backfill existing orders and escrow seller amounts
-- ===========================================================================

UPDATE public.orders
SET seller_commission_rate = 0.05,
    seller_commission_base = ROUND(COALESCE(subtotal, 0), 2),
    seller_commission_amount = public.seller_commission_amount(subtotal, 0.05)
WHERE seller_commission_amount IS NULL
   OR seller_commission_base IS NULL
   OR seller_commission_rate IS NULL;

UPDATE public.orders o
SET seller_commission_status = 'earned'::public.seller_commission_status_enum,
    seller_commission_recognized_at = COALESCE(o.seller_commission_recognized_at, e.released_at, now())
FROM public.escrow e
WHERE e.order_id = o.order_id
  AND e.status = 'released'::public.escrow_status_enum
  AND o.seller_commission_status = 'pending'::public.seller_commission_status_enum;

UPDATE public.orders o
SET seller_commission_status = 'reversed'::public.seller_commission_status_enum,
    seller_commission_reversed_at = COALESCE(o.seller_commission_reversed_at, e.refunded_at, now())
FROM public.escrow e
WHERE e.order_id = o.order_id
  AND e.status = 'refunded'::public.escrow_status_enum
  AND o.seller_commission_status IN (
    'pending'::public.seller_commission_status_enum,
    'earned'::public.seller_commission_status_enum
  );

UPDATE public.orders o
SET seller_commission_status = 'void'::public.seller_commission_status_enum
WHERE o.order_status = 'cancelled'::public.order_status_enum
  AND o.seller_commission_status = 'pending'::public.seller_commission_status_enum
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.order_id = o.order_id
      AND p.payment_status = 'paid'::public.payment_status_enum
  );

UPDATE public.escrow e
SET seller_amount_centavos = GREATEST(
  0,
  e.amount_centavos
    - ROUND(COALESCE(o.platform_fee, 0) * 100)::integer
    - ROUND(COALESCE(o.seller_commission_amount, 0) * 100)::integer
)
FROM public.orders o
WHERE o.order_id = e.order_id
  AND e.status IN (
    'held'::public.escrow_status_enum,
    'disputed'::public.escrow_status_enum,
    'released'::public.escrow_status_enum
  );
