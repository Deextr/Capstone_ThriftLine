-- Block users from favoriting their own listings; remove existing self-favorites.

DELETE FROM public.saved_items si
USING public.products p
WHERE si.product_id = p.product_id
  AND si.user_id = p.seller_id;

DROP POLICY IF EXISTS saved_items_insert_own ON public.saved_items;
CREATE POLICY saved_items_insert_own ON public.saved_items
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.products p
      WHERE p.product_id = saved_items.product_id
        AND p.seller_id = auth.uid()
    )
  );
