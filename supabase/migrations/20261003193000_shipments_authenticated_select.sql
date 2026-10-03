-- Fix authenticated reads of public.shipments for PostgREST order embeds.
--
-- Phase 7 granted column-level SELECT only. PostgREST nested selects on
-- shipments (orders → shipments FK) require table-level SELECT. RLS policy
-- shipments_select_participant still restricts rows to order buyer/seller/admin.
-- delivery_failure_details (20261002170000) was never added to the column grant.

BEGIN;

DROP POLICY IF EXISTS shipments_select_participant ON public.shipments;
CREATE POLICY shipments_select_participant ON public.shipments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.order_id = shipments.order_id
        AND (
          o.buyer_id = auth.uid()
          OR o.seller_id = auth.uid()
          OR public.is_admin()
        )
    )
  );

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.shipments
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.shipments TO authenticated;

COMMIT;
