-- Phase A seller payouts: the seller requests, the team sends GCash manually
-- outside ThriftLine, and an admin records the confirmed transfer.
-- ThriftLine never sends money to sellers.
--
-- Ledger: available = released escrow - (requested + paid payouts).
-- requested reserves funds; paid keeps them deducted; rejected / cancelled
-- release the reservation.
--
-- Requires 20261016155900_seller_payout_status_values.sql to have run first.
-- Does not rewrite previously applied migrations.

-- ===========================================================================
-- 1. Columns, constraints, indexes
-- ===========================================================================

ALTER TABLE public.seller_payouts
  ADD COLUMN IF NOT EXISTS transferred_amount_centavos integer,
  ADD COLUMN IF NOT EXISTS gcash_reference text,
  ADD COLUMN IF NOT EXISTS transferred_at timestamptz,
  ADD COLUMN IF NOT EXISTS evidence_path text,
  ADD COLUMN IF NOT EXISTS processed_by uuid REFERENCES public.users (user_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_note text,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.seller_payouts
  DROP CONSTRAINT IF EXISTS seller_payouts_paid_record_chk;
ALTER TABLE public.seller_payouts
  ADD CONSTRAINT seller_payouts_paid_record_chk
  CHECK (
    status IS DISTINCT FROM 'paid'::public.seller_payout_status_enum
    OR (
      gcash_reference IS NOT NULL
      AND transferred_at IS NOT NULL
      AND processed_by IS NOT NULL
      AND processed_at IS NOT NULL
      AND evidence_path IS NOT NULL
      AND transferred_amount_centavos = amount_centavos
    )
  );

ALTER TABLE public.seller_payouts
  DROP CONSTRAINT IF EXISTS seller_payouts_rejected_reason_chk;
ALTER TABLE public.seller_payouts
  ADD CONSTRAINT seller_payouts_rejected_reason_chk
  CHECK (
    status IS DISTINCT FROM 'rejected'::public.seller_payout_status_enum
    OR (rejection_reason IS NOT NULL AND processed_by IS NOT NULL)
  );

-- Older data may hold several open requests per seller. Keep the newest one
-- open and cancel the rest so their reserved amount returns to available.
UPDATE public.seller_payouts p
SET status = 'cancelled'::public.seller_payout_status_enum,
    cancelled_at = now(),
    admin_note = 'Cancelled automatically: only one open payout request is allowed per seller.'
WHERE p.status = 'requested'::public.seller_payout_status_enum
  AND EXISTS (
    SELECT 1 FROM public.seller_payouts newer
    WHERE newer.seller_id = p.seller_id
      AND newer.status = 'requested'::public.seller_payout_status_enum
      AND (newer.requested_at, newer.payout_id) > (p.requested_at, p.payout_id)
  );

CREATE UNIQUE INDEX IF NOT EXISTS seller_payouts_one_open_request_uidx
  ON public.seller_payouts (seller_id)
  WHERE status = 'requested'::public.seller_payout_status_enum;

CREATE INDEX IF NOT EXISTS seller_payouts_status_idx
  ON public.seller_payouts (status, requested_at DESC);

DROP TRIGGER IF EXISTS trg_seller_payouts_updated_at ON public.seller_payouts;
CREATE TRIGGER trg_seller_payouts_updated_at
BEFORE UPDATE ON public.seller_payouts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.seller_payouts IS
  'Seller payout requests (Phase A). The team sends GCash manually outside ThriftLine; an admin records the confirmed transfer. ThriftLine does not send money.';

-- ===========================================================================
-- 2. Ledger
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
        AND status IN (
          'requested'::public.seller_payout_status_enum,
          'paid'::public.seller_payout_status_enum
        )
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
-- 3. Seller: request + cancel
-- ===========================================================================

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

  IF EXISTS (
    SELECT 1 FROM public.seller_payouts
    WHERE seller_id = v_uid
      AND status = 'requested'::public.seller_payout_status_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have a payout request waiting. Wait for it to be completed or cancel it first.'
    );
  END IF;

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
    'Payout request recorded',
    'Your payout request of ' || public._peso_text(v_amount) ||
      ' was recorded. The ThriftLine team will send it to GCash ' || v_mobile ||
      ' and you will be notified once the transfer is recorded.',
    jsonb_build_object('payout_id', v_payout_id),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object(
    'success', true,
    'payout_id', v_payout_id,
    'amount_centavos', v_amount,
    'available_centavos', public.seller_available_centavos(v_uid)
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You already have a payout request waiting.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.request_seller_payout(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_seller_payout(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_my_seller_payout(p_payout_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_payout public.seller_payouts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('seller-payout:' || v_uid::text));

  SELECT * INTO v_payout
  FROM public.seller_payouts
  WHERE payout_id = p_payout_id
  FOR UPDATE;

  IF NOT FOUND OR v_payout.seller_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payout request not found.');
  END IF;

  IF v_payout.status = 'cancelled'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object('success', true, 'already_cancelled', true);
  END IF;

  IF v_payout.status IS DISTINCT FROM 'requested'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a waiting payout request can be cancelled.'
    );
  END IF;

  UPDATE public.seller_payouts
  SET status = 'cancelled'::public.seller_payout_status_enum,
      cancelled_at = now()
  WHERE payout_id = v_payout.payout_id
    AND status = 'requested'::public.seller_payout_status_enum;

  RETURN jsonb_build_object(
    'success', true,
    'available_centavos', public.seller_available_centavos(v_uid)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_my_seller_payout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_seller_payout(uuid) TO authenticated;

-- ===========================================================================
-- 4. Admin: list, record transfer, reject
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.admin_list_seller_payouts(
  p_status text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status text := NULLIF(lower(btrim(coalesce(p_status, ''))), '');
  v_search text := NULLIF(btrim(coalesce(p_search, '')), '');
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 25), 100));
  v_offset integer := GREATEST(0, COALESCE(p_offset, 0));
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_counts jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required.');
  END IF;

  IF v_status IS NOT NULL AND v_status NOT IN ('requested', 'paid', 'rejected', 'cancelled') THEN
    v_status := NULL;
  END IF;

  WITH filtered AS (
    SELECT p.*, u.full_name, u.email, sp.shop_name
    FROM public.seller_payouts p
    JOIN public.users u ON u.user_id = p.seller_id
    LEFT JOIN public.seller_profiles sp ON sp.seller_id = p.seller_id
    WHERE (v_status IS NULL OR p.status::text = v_status)
      AND (
        v_search IS NULL
        OR p.payout_id::text = v_search
        OR u.full_name ILIKE '%' || v_search || '%'
        OR u.email ILIKE '%' || v_search || '%'
        OR sp.shop_name ILIKE '%' || v_search || '%'
        OR p.gcash_mobile_number ILIKE '%' || v_search || '%'
        OR p.gcash_reference ILIKE '%' || v_search || '%'
      )
  )
  SELECT
    (SELECT COUNT(*) FROM filtered),
    COALESCE((
      SELECT jsonb_agg(row_item ORDER BY sort_requested DESC)
      FROM (
        SELECT
          jsonb_build_object(
            'payout_id', f.payout_id,
            'seller_id', f.seller_id,
            'seller_name', f.full_name,
            'seller_email', f.email,
            'shop_name', f.shop_name,
            'amount_centavos', f.amount_centavos,
            'status', f.status::text,
            'requested_at', f.requested_at,
            'gcash_account_name', f.gcash_account_name,
            'gcash_mobile_number', f.gcash_mobile_number,
            'gcash_reference', f.gcash_reference,
            'transferred_amount_centavos', f.transferred_amount_centavos,
            'transferred_at', f.transferred_at,
            'evidence_path', f.evidence_path,
            'processed_by', f.processed_by,
            'processed_at', f.processed_at,
            'admin_note', f.admin_note,
            'rejection_reason', f.rejection_reason,
            'cancelled_at', f.cancelled_at,
            'seller_available_centavos', public.seller_available_centavos(f.seller_id)
          ) AS row_item,
          f.requested_at AS sort_requested
        FROM filtered f
        ORDER BY f.requested_at DESC
        LIMIT v_limit OFFSET v_offset
      ) page
    ), '[]'::jsonb)
  INTO v_total, v_items;

  SELECT jsonb_build_object(
    'requested', COUNT(*) FILTER (WHERE status = 'requested'::public.seller_payout_status_enum),
    'paid', COUNT(*) FILTER (WHERE status = 'paid'::public.seller_payout_status_enum),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'::public.seller_payout_status_enum),
    'cancelled', COUNT(*) FILTER (WHERE status = 'cancelled'::public.seller_payout_status_enum)
  )
  INTO v_counts
  FROM public.seller_payouts;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'items', v_items,
    'counts', v_counts
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_seller_payouts(text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_seller_payouts(text, text, integer, integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_seller_payout_paid(
  p_payout_id uuid,
  p_transferred_amount_centavos integer,
  p_gcash_reference text,
  p_transferred_at timestamptz,
  p_evidence_path text DEFAULT NULL,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_payout public.seller_payouts%ROWTYPE;
  v_reference text := btrim(coalesce(p_gcash_reference, ''));
  v_note text := NULLIF(btrim(coalesce(p_admin_note, '')), '');
  v_evidence text := NULLIF(btrim(coalesce(p_evidence_path, '')), '');
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can record a payout transfer.');
  END IF;

  SELECT * INTO v_payout
  FROM public.seller_payouts
  WHERE payout_id = p_payout_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payout request not found.');
  END IF;

  IF v_payout.status = 'paid'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object('success', true, 'already_recorded', true);
  END IF;

  IF v_payout.status IS DISTINCT FROM 'requested'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a waiting payout request can be marked as paid.'
    );
  END IF;

  IF p_transferred_amount_centavos IS DISTINCT FROM v_payout.amount_centavos THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The amount sent must equal the requested ' ||
        public._peso_text(v_payout.amount_centavos) ||
        '. If you sent a different amount, reject this request and ask the seller to request again.'
    );
  END IF;

  IF char_length(v_reference) NOT BETWEEN 4 AND 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash reference number.');
  END IF;

  IF p_transferred_at IS NULL
     OR p_transferred_at > now() + interval '1 hour'
     OR p_transferred_at < v_payout.requested_at - interval '1 day' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the date the GCash transfer was sent.');
  END IF;

  IF v_evidence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Attach the GCash receipt for this transfer.');
  END IF;

  IF v_evidence NOT LIKE 'payouts/' || v_payout.seller_id::text || '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'The receipt file is not linked to this payout.');
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 1,000 characters.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seller_payouts
    WHERE gcash_reference = v_reference
      AND payout_id IS DISTINCT FROM v_payout.payout_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This GCash reference is already recorded on another payout.'
    );
  END IF;

  UPDATE public.seller_payouts
  SET status = 'paid'::public.seller_payout_status_enum,
      transferred_amount_centavos = p_transferred_amount_centavos,
      gcash_reference = v_reference,
      transferred_at = p_transferred_at,
      evidence_path = v_evidence,
      admin_note = v_note,
      processed_by = v_uid,
      processed_at = now()
  WHERE payout_id = v_payout.payout_id
    AND status = 'requested'::public.seller_payout_status_enum;

  INSERT INTO public.admin_audit_logs (
    category, event_type, status, summary, actor_user_id, target_type, target_id, details
  )
  VALUES (
    'payments_escrow',
    'seller_payout_paid',
    'success',
    'Recorded GCash payout of ' || public._peso_text(v_payout.amount_centavos),
    v_uid,
    'seller_payout',
    v_payout.payout_id::text,
    jsonb_build_object(
      'seller_id', v_payout.seller_id,
      'amount_centavos', v_payout.amount_centavos,
      'gcash_reference', v_reference,
      'transferred_at', p_transferred_at,
      'has_evidence', v_evidence IS NOT NULL
    )
  );

  PERFORM public.notify_user(
    v_payout.seller_id,
    'system',
    'Payout sent',
    'The ThriftLine team sent ' || public._peso_text(v_payout.amount_centavos) ||
      ' to your GCash. Reference: ' || v_reference || '.',
    jsonb_build_object('payout_id', v_payout.payout_id),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object('success', true, 'status', 'paid');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_seller_payout_paid(
  uuid, integer, text, timestamptz, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_seller_payout_paid(
  uuid, integer, text, timestamptz, text, text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reject_seller_payout(
  p_payout_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_payout public.seller_payouts%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can reject a payout request.');
  END IF;

  IF char_length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Give the seller a short reason (5 to 500 characters).');
  END IF;

  SELECT * INTO v_payout
  FROM public.seller_payouts
  WHERE payout_id = p_payout_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payout request not found.');
  END IF;

  IF v_payout.status = 'rejected'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object('success', true, 'already_rejected', true);
  END IF;

  IF v_payout.status IS DISTINCT FROM 'requested'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a waiting payout request can be rejected.'
    );
  END IF;

  UPDATE public.seller_payouts
  SET status = 'rejected'::public.seller_payout_status_enum,
      rejection_reason = v_reason,
      processed_by = v_uid,
      processed_at = now()
  WHERE payout_id = v_payout.payout_id
    AND status = 'requested'::public.seller_payout_status_enum;

  INSERT INTO public.admin_audit_logs (
    category, event_type, status, summary, actor_user_id, target_type, target_id, details
  )
  VALUES (
    'payments_escrow',
    'seller_payout_rejected',
    'success',
    'Rejected payout request of ' || public._peso_text(v_payout.amount_centavos),
    v_uid,
    'seller_payout',
    v_payout.payout_id::text,
    jsonb_build_object(
      'seller_id', v_payout.seller_id,
      'amount_centavos', v_payout.amount_centavos,
      'reason', v_reason
    )
  );

  PERFORM public.notify_user(
    v_payout.seller_id,
    'system',
    'Payout request not completed',
    'Your payout request of ' || public._peso_text(v_payout.amount_centavos) ||
      ' was not sent: ' || v_reason || ' The amount is available again.',
    jsonb_build_object('payout_id', v_payout.payout_id),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object('success', true, 'status', 'rejected');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_seller_payout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_seller_payout(uuid, text) TO authenticated;

-- ===========================================================================
-- 5. Private financial evidence bucket (admin only)
-- ===========================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'financial-evidence',
  'financial-evidence',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS financial_evidence_insert_admin ON storage.objects;
CREATE POLICY financial_evidence_insert_admin ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'financial-evidence'
    AND public.is_admin()
    AND split_part(name, '/', 1) IN ('payouts', 'refunds')
  );

DROP POLICY IF EXISTS financial_evidence_select_admin ON storage.objects;
CREATE POLICY financial_evidence_select_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'financial-evidence' AND public.is_admin());
