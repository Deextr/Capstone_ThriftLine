-- Pending PayMongo recovery: protect open checkouts longer; auction 1-hour payment reminder.

CREATE OR REPLACE FUNCTION public.fixed_price_checkout_has_live_session(
  p_order_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders target
    JOIN public.orders o
      ON o.order_id = target.order_id
      OR (
        target.checkout_group_id IS NOT NULL
        AND o.checkout_group_id = target.checkout_group_id
      )
    JOIN public.payments p ON p.order_id = o.order_id
    WHERE target.order_id = p_order_id
      AND o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::public.order_type_enum
      AND p.payment_status = 'pending'::public.payment_status_enum
      AND p.checkout_session_id IS NOT NULL
      AND p.updated_at > now() - interval '90 minutes'
  );
$$;

COMMENT ON FUNCTION public.fixed_price_checkout_has_live_session(uuid) IS
  'True while a fixed-price order has a PayMongo session still within the 90-minute reservation window.';

CREATE OR REPLACE FUNCTION public.restore_my_unpaid_fixed_price_checkouts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_buyer uuid;
  v_count integer := 0;
  r record;
BEGIN
  v_buyer := auth.uid();
  IF v_buyer IS NULL THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT o.order_id, o.created_at
    FROM public.orders o
    WHERE o.buyer_id = v_buyer
      AND o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NULL
      AND o.order_type IS DISTINCT FROM 'auction'::public.order_type_enum
    FOR UPDATE OF o
  LOOP
    IF r.created_at > now() - interval '90 minutes' THEN
      CONTINUE;
    END IF;
    IF public.fixed_price_checkout_has_live_session(r.order_id) THEN
      CONTINUE;
    END IF;
    PERFORM public.void_unpaid_checkout(r.order_id, true, false);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.restore_my_unpaid_fixed_price_checkouts() IS
  'Voids abandoned fixed-price checkouts past the reservation window. Skips live PayMongo sessions.';

CREATE OR REPLACE FUNCTION public.notify_auction_payment_due_one_hour_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
  r record;
  v_title text;
  v_body text;
  v_product text;
BEGIN
  FOR r IN
    SELECT
      o.order_id,
      o.buyer_id,
      o.auction_id,
      o.payment_due_at,
      COALESCE(
        NULLIF(btrim(oi.product_name), ''),
        NULLIF(btrim(p.title), ''),
        'this item'
      ) AS product_label
    FROM public.orders o
    LEFT JOIN public.order_items oi ON oi.order_id = o.order_id
    LEFT JOIN public.products p ON p.product_id = oi.product_id
    WHERE o.order_status = 'pending'::public.order_status_enum
      AND o.auction_id IS NOT NULL
      AND o.payment_due_at IS NOT NULL
      AND o.payment_due_at > now()
      AND o.payment_due_at <= now() + interval '1 hour'
      AND NOT EXISTS (
        SELECT 1
        FROM public.payments pay
        WHERE pay.order_id = o.order_id
          AND pay.payment_status = 'paid'::public.payment_status_enum
      )
  LOOP
    IF r.buyer_id IS NULL OR r.auction_id IS NULL THEN
      CONTINUE;
    END IF;

    v_product := COALESCE(r.product_label, 'this item');
    v_title := '1 hour left to pay';
    v_body :=
      'You have 1 hour remaining to complete payment for '
      || v_product
      || '. Open your order to pay now.';

    PERFORM public.notify_auction_event_once(
      r.buyer_id,
      'wonBid',
      v_title,
      v_body,
      r.auction_id,
      'payment_due_1h',
      jsonb_build_object(
        'order_id', r.order_id,
        'payment_due_at', r.payment_due_at
      ),
      'buyer'::public.notification_audience_enum
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_auction_payment_due_one_hour_reminders()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_auction_payment_due_one_hour_reminders()
  TO postgres, service_role;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not enabled; skip scheduling auction payment due reminders.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname = 'thriftline-auction-payment-due-1h'
  ) THEN
    PERFORM cron.unschedule('thriftline-auction-payment-due-1h');
  END IF;

  PERFORM cron.schedule(
    'thriftline-auction-payment-due-1h',
    '*/10 * * * *',
    $cron$SELECT public.notify_auction_payment_due_one_hour_reminders();$cron$
  );
EXCEPTION
  WHEN undefined_table OR undefined_object THEN
    RAISE NOTICE 'Could not schedule auction payment due reminders: %', SQLERRM;
  WHEN OTHERS THEN
    RAISE WARNING 'Could not schedule auction payment due reminders: %', SQLERRM;
END;
$$;
