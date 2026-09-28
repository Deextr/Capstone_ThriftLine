-- Migration: 20260907020000_cart_items.sql
-- Description: Creates cart_items table with RLS, triggers, indexes, and add_to_cart function

-- 1. Create table public.cart_items
CREATE TABLE IF NOT EXISTS public.cart_items (
    cart_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(product_id) ON DELETE CASCADE,
    quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cart_items_user_product_unique UNIQUE (user_id, product_id)
);

-- 2. Indexes for efficient user and product lookups
CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items (user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items (product_id);

-- 3. Trigger for updated_at
DROP TRIGGER IF EXISTS trg_cart_items_updated_at ON public.cart_items;
CREATE TRIGGER trg_cart_items_updated_at
    BEFORE UPDATE ON public.cart_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items FORCE ROW LEVEL SECURITY;

-- 5. RLS Policies
DROP POLICY IF EXISTS cart_items_select_own ON public.cart_items;
CREATE POLICY cart_items_select_own ON public.cart_items
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS cart_items_insert_own ON public.cart_items;
CREATE POLICY cart_items_insert_own ON public.cart_items
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS cart_items_update_own ON public.cart_items;
CREATE POLICY cart_items_update_own ON public.cart_items
    FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS cart_items_delete_own ON public.cart_items;
CREATE POLICY cart_items_delete_own ON public.cart_items
    FOR DELETE USING (auth.uid() = user_id);

-- 6. Grant access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cart_items TO authenticated;

-- 7. Cart helper function: add_to_cart
CREATE OR REPLACE FUNCTION public.add_to_cart(p_product_id uuid, p_quantity integer DEFAULT 1)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
    v_cart_item public.cart_items%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    INSERT INTO public.cart_items (user_id, product_id, quantity)
    VALUES (v_user_id, p_product_id, GREATEST(COALESCE(p_quantity, 1), 1))
    ON CONFLICT (user_id, product_id)
    DO UPDATE SET
        quantity = public.cart_items.quantity + EXCLUDED.quantity,
        updated_at = now()
    RETURNING * INTO v_cart_item;

    RETURN row_to_json(v_cart_item);
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_to_cart(uuid, integer) TO authenticated;
