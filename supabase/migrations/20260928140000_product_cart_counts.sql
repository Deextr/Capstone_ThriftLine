-- Public cart popularity for product cards.
-- cart_items RLS only allows a buyer to read their own rows, so a SECURITY
-- DEFINER aggregate is required. Returns counts only — never user ids.

CREATE OR REPLACE FUNCTION public.product_cart_counts(p_product_ids uuid[])
RETURNS TABLE (product_id uuid, cart_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.product_id, COUNT(*)::bigint AS cart_count
  FROM public.cart_items c
  WHERE p_product_ids IS NOT NULL
    AND cardinality(p_product_ids) > 0
    AND c.product_id = ANY (p_product_ids)
  GROUP BY c.product_id;
$$;

REVOKE ALL ON FUNCTION public.product_cart_counts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.product_cart_counts(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.product_cart_counts(uuid[]) TO anon;
