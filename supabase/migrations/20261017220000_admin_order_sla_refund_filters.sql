-- Admin order filters: shared SLA overdue + buyer refund classification
-- (matches fulfillment_overdue_count and admin_list_buyer_refunds).

CREATE OR REPLACE FUNCTION public.order_fulfillment_overdue(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.order_is_stuck_preparing(p_order_id)
    AND public.order_paid_at(p_order_id) IS NOT NULL
    AND public.order_paid_at(p_order_id) <= now() - interval '72 hours';
$$;

COMMENT ON FUNCTION public.order_fulfillment_overdue(uuid) IS
  'Paid order stuck preparing past 72h (same rule as fulfillment_overdue_count).';

REVOKE ALL ON FUNCTION public.order_fulfillment_overdue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.order_fulfillment_overdue(uuid) TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.order_buyer_refund_needs_action(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.escrow e
    WHERE e.order_id = p_order_id
      AND e.status = 'refunded'::public.escrow_status_enum
      AND e.refund_state = 'manual_required'::public.escrow_refund_state_enum
  );
$$;

COMMENT ON FUNCTION public.order_buyer_refund_needs_action(uuid) IS
  'Manual GCash refund awaiting admin action (admin_list_buyer_refunds needs_action).';

REVOKE ALL ON FUNCTION public.order_buyer_refund_needs_action(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.order_buyer_refund_needs_action(uuid) TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.order_buyer_refund_completed(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.order_id = p_order_id
      AND p.payment_status = 'refunded'::public.payment_status_enum
  )
  OR EXISTS (
    SELECT 1
    FROM public.escrow e
    WHERE e.order_id = p_order_id
      AND e.status = 'refunded'::public.escrow_status_enum
      AND e.refund_state IN (
        'succeeded'::public.escrow_refund_state_enum,
        'manual_completed'::public.escrow_refund_state_enum
      )
  );
$$;

COMMENT ON FUNCTION public.order_buyer_refund_completed(uuid) IS
  'Buyer refund financially completed (PayMongo succeeded or manual GCash marked done).';

REVOKE ALL ON FUNCTION public.order_buyer_refund_completed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.order_buyer_refund_completed(uuid) TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.fulfillment_overdue_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN (
    SELECT count(*)::integer
    FROM public.orders o
    WHERE public.order_fulfillment_overdue(o.order_id)
  );
END;
$$;

CREATE OR REPLACE VIEW public.admin_order_sla_flags
WITH (security_invoker = true)
AS
SELECT
  o.order_id,
  public.order_fulfillment_overdue(o.order_id) AS fulfillment_overdue,
  public.order_buyer_refund_needs_action(o.order_id) AS refund_needs_action,
  public.order_buyer_refund_completed(o.order_id) AS refund_completed
FROM public.orders o;

COMMENT ON VIEW public.admin_order_sla_flags IS
  '@primaryKey order_id '
  '@foreignKey (order_id) references public.orders (order_id) '
  'Per-order admin SLA/refund flags for PostgREST embed on orders.order_id.';

REVOKE ALL ON TABLE public.admin_order_sla_flags FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.admin_order_sla_flags TO authenticated, postgres, service_role;
