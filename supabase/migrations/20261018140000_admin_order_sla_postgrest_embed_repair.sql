-- Ensure PostgREST can embed admin_order_sla_flags on orders (Orders & Transactions admin list).
-- Idempotent repair; safe if 20261017220000 already applied.

BEGIN;

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

NOTIFY pgrst, 'reload schema';

COMMIT;
