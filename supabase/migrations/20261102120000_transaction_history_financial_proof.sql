-- Let buyers and sellers read their own financial-evidence objects (signed URLs).
-- Expose proof availability on transaction / payout list RPCs (not raw paths in lists).

DROP POLICY IF EXISTS financial_evidence_select_owner ON storage.objects;
CREATE POLICY financial_evidence_select_owner ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'financial-evidence'
    AND (
      EXISTS (
        SELECT 1
        FROM public.seller_payouts sp
        WHERE sp.seller_id = auth.uid()
          AND sp.evidence_path = objects.name
      )
      OR EXISTS (
        SELECT 1
        FROM public.escrow_refund_details erd
        WHERE erd.buyer_id = auth.uid()
          AND erd.manual_evidence_path = objects.name
      )
    )
  );

DROP FUNCTION IF EXISTS public.list_my_payment_transactions();

CREATE OR REPLACE FUNCTION public.list_my_payment_transactions()
RETURNS TABLE (
  payment_id uuid,
  order_id uuid,
  order_number text,
  product_title text,
  product_image_url text,
  paid_at timestamptz,
  amount_centavos integer,
  payment_status text,
  payment_method text,
  paymongo_channel text,
  transaction_reference text,
  refunded_at timestamptz,
  refund_amount_centavos integer,
  refund_provider_status text,
  escrow_id uuid,
  refund_state text,
  refund_completed_at timestamptz,
  refund_transfer_link text,
  refund_transfer_link_expires_at timestamptz,
  refund_gcash_submitted boolean,
  manual_refund_reference text,
  refund_proof_available boolean
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
    COALESCE(lead_oi.title, 'Order'::text) AS product_title,
    COALESCE(
      lead_oi.item_image_url,
      (
        SELECT NULLIF(btrim(pi.image_url::text), '')
        FROM public.product_images pi
        WHERE pi.product_id = lead_oi.product_id
        ORDER BY pi.is_primary DESC, pi.display_order ASC, pi.created_at ASC
        LIMIT 1
      )
    ) AS product_image_url,
    public.order_paid_at(o.order_id) AS paid_at,
    COALESCE(
      p.amount_centavos,
      (round(p.total_amount * 100))::integer
    ) AS amount_centavos,
    p.payment_status::text,
    p.payment_method::text,
    p.paymongo_channel::text,
    p.transaction_reference::text,
    e.refunded_at,
    CASE
      WHEN e.status = 'refunded'::public.escrow_status_enum
        THEN COALESCE(e.amount_centavos, p.amount_centavos)
      ELSE NULL
    END AS refund_amount_centavos,
    e.refund_provider_status::text,
    e.escrow_id,
    e.refund_state::text,
    e.refund_completed_at,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link
      ELSE NULL
    END AS refund_transfer_link,
    CASE
      WHEN e.refund_state = 'awaiting_buyer_claim'::public.escrow_refund_state_enum
        THEN d.transfer_link_expires_at
      ELSE NULL
    END AS refund_transfer_link_expires_at,
    (d.gcash_submitted_at IS NOT NULL) AS refund_gcash_submitted,
    d.manual_reference AS manual_refund_reference,
    (
      d.manual_evidence_path IS NOT NULL
      AND btrim(d.manual_evidence_path) <> ''
    ) AS refund_proof_available
  FROM public.payments p
  JOIN public.orders o ON o.order_id = p.order_id
  LEFT JOIN LATERAL (
    SELECT
      oi.title::text AS title,
      oi.product_id,
      NULLIF(btrim(oi.image_url::text), '') AS item_image_url
    FROM public.order_items oi
    WHERE oi.order_id = o.order_id
    ORDER BY
      oi.line_total DESC NULLS LAST,
      oi.created_at ASC,
      oi.order_item_id ASC
    LIMIT 1
  ) lead_oi ON TRUE
  LEFT JOIN public.escrow e ON e.order_id = o.order_id
  LEFT JOIN public.escrow_refund_details d ON d.escrow_id = e.escrow_id
  WHERE o.buyer_id = v_uid
    AND p.payment_status IN (
      'paid'::public.payment_status_enum,
      'refunded'::public.payment_status_enum
    )
  ORDER BY COALESCE(e.refunded_at, public.order_paid_at(o.order_id), p.updated_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_payment_transactions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_payment_transactions()
  TO authenticated, postgres, service_role;

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
      'has_payout_proof', (
        p.evidence_path IS NOT NULL AND btrim(p.evidence_path) <> ''
      ),
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
