-- Phase 1 â€” saved_items hardening and RLS policies.

ALTER TABLE public.saved_items
  ALTER COLUMN saved_item_id SET DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS saved_items_user_product_unique
  ON public.saved_items (user_id, product_id);

CREATE INDEX IF NOT EXISTS saved_items_user_id_idx ON public.saved_items (user_id);
CREATE INDEX IF NOT EXISTS saved_items_product_id_idx ON public.saved_items (product_id);

ALTER TABLE public.saved_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS saved_items_select_own ON public.saved_items;
CREATE POLICY saved_items_select_own ON public.saved_items
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS saved_items_insert_own ON public.saved_items;
CREATE POLICY saved_items_insert_own ON public.saved_items
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS saved_items_delete_own ON public.saved_items;
CREATE POLICY saved_items_delete_own ON public.saved_items
  FOR DELETE USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.saved_items TO authenticated;
