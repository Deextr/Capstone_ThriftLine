-- Fix seller_earnings_snapshot activity/payout aggregation.
--
-- jsonb_agg(item ORDER BY item.sort_at) treats "item" as a table, so Postgres
-- raises 42P01: missing FROM-clause entry for table "item".
-- The subquery alias is "listed"; sort by listed.sort_at.
-- Totals stay the same: held+disputed, released, refunded, payout requested.

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

REVOKE ALL ON FUNCTION public.seller_earnings_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_earnings_snapshot() TO authenticated;
