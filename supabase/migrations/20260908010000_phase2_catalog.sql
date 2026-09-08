-- Phase 2 — Catalog and discovery.
-- Products search/indexes/quantity, follows, looking_for_posts columns,
-- view-count RPC, and saved_items favorite_count trigger (repo copy).

-- ---------------------------------------------------------------------------
-- products.title → name (Flutter already writes `name`)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'title'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'name'
  ) THEN
    ALTER TABLE public.products RENAME COLUMN title TO name;
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'title'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'name'
  ) THEN
    UPDATE public.products
    SET name = title
    WHERE (name IS NULL OR btrim(name) = '')
      AND title IS NOT NULL;
  END IF;
END $$;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS quantity_available integer NOT NULL DEFAULT 1;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS sold_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'search_vector'
  ) THEN
    ALTER TABLE public.products
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(brand, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'C')
      ) STORED;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS products_search_vector_gin
  ON public.products USING gin (search_vector);

CREATE INDEX IF NOT EXISTS products_status_created_at_idx
  ON public.products (status, created_at DESC);

CREATE INDEX IF NOT EXISTS products_seller_id_status_idx
  ON public.products (seller_id, status);

CREATE INDEX IF NOT EXISTS products_category_id_status_idx
  ON public.products (category_id, status);

CREATE INDEX IF NOT EXISTS products_price_idx
  ON public.products (price);

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_quantity_available_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_quantity_available_check
  CHECK (quantity_available >= 0);

-- ---------------------------------------------------------------------------
-- View counts: clients must not UPDATE products.views. Use this RPC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.increment_product_view(p_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.products
  SET views = views + 1
  WHERE product_id = p_product_id
    AND status IN ('active'::product_status_enum, 'sold'::product_status_enum);
END;
$$;

REVOKE ALL ON FUNCTION public.increment_product_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_product_view(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- saved_items → products.favorite_count (may already exist in older databases)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_saved_items_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.products
    SET favorite_count = favorite_count + 1,
        updated_at = now()
    WHERE product_id = NEW.product_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.products
    SET favorite_count = greatest(favorite_count - 1, 0),
        updated_at = now()
    WHERE product_id = OLD.product_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_saved_items_favorite_count ON public.saved_items;
CREATE TRIGGER trg_saved_items_favorite_count
AFTER INSERT OR DELETE ON public.saved_items
FOR EACH ROW EXECUTE FUNCTION public.handle_saved_items_change();

-- ---------------------------------------------------------------------------
-- follows
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
  follower_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CONSTRAINT follows_no_self CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS follows_following_id_idx ON public.follows (following_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS follows_select_authenticated ON public.follows;
CREATE POLICY follows_select_authenticated ON public.follows
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS follows_insert_own ON public.follows;
CREATE POLICY follows_insert_own ON public.follows
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS follows_delete_own ON public.follows;
CREATE POLICY follows_delete_own ON public.follows
  FOR DELETE TO authenticated
  USING (auth.uid() = follower_id);

GRANT SELECT, INSERT, DELETE ON public.follows TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_follows_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.seller_profiles
    SET follower_count = follower_count + 1
    WHERE seller_id = NEW.following_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.seller_profiles
    SET follower_count = greatest(follower_count - 1, 0)
    WHERE seller_id = OLD.following_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_follows_count ON public.follows;
CREATE TRIGGER trg_follows_count
AFTER INSERT OR DELETE ON public.follows
FOR EACH ROW EXECUTE FUNCTION public.handle_follows_count();

-- ---------------------------------------------------------------------------
-- looking_for_posts: columns the Flutter model already expects
-- ---------------------------------------------------------------------------
ALTER TABLE public.looking_for_posts
  ADD COLUMN IF NOT EXISTS description text;

ALTER TABLE public.looking_for_posts
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.categories (category_id);

ALTER TABLE public.looking_for_posts
  ADD COLUMN IF NOT EXISTS location character varying(255);

ALTER TABLE public.looking_for_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.looking_for_posts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS looking_for_posts_select_all ON public.looking_for_posts;
CREATE POLICY looking_for_posts_select_all ON public.looking_for_posts
  FOR SELECT
  USING (
    status = 'open'::looking_for_status_enum
    OR auth.uid() = user_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS looking_for_posts_insert_own ON public.looking_for_posts;
CREATE POLICY looking_for_posts_insert_own ON public.looking_for_posts
  FOR INSERT
  WITH CHECK (auth.uid() = user_id AND status = 'open'::looking_for_status_enum);

DROP POLICY IF EXISTS looking_for_posts_update_own_admin ON public.looking_for_posts;
CREATE POLICY looking_for_posts_update_own_admin ON public.looking_for_posts
  FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS looking_for_posts_delete_own_admin ON public.looking_for_posts;
CREATE POLICY looking_for_posts_delete_own_admin ON public.looking_for_posts
  FOR DELETE
  USING (auth.uid() = user_id OR public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.looking_for_posts TO authenticated;
GRANT SELECT ON public.looking_for_posts TO anon;
