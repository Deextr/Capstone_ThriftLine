-- Verify admin_order_sla_flags helpers (run as postgres/service_role on seeded data).
-- Expect: fulfillment_overdue only for stuck preparing + paid clock > 72h;
-- refund_completed excludes manual_required; refund_needs_action only manual_required.

SELECT
  o.order_id,
  o.order_status,
  public.order_fulfillment_overdue(o.order_id) AS fulfillment_overdue,
  public.order_buyer_refund_needs_action(o.order_id) AS refund_needs_action,
  public.order_buyer_refund_completed(o.order_id) AS refund_completed
FROM public.orders o
WHERE public.order_fulfillment_overdue(o.order_id)
   OR public.order_buyer_refund_needs_action(o.order_id)
   OR public.order_buyer_refund_completed(o.order_id)
ORDER BY o.created_at DESC
LIMIT 50;

SELECT public.fulfillment_overdue_count() AS dashboard_overdue_count;

SELECT count(*) AS delayed_filter_count
FROM public.admin_order_sla_flags f
WHERE f.fulfillment_overdue;
