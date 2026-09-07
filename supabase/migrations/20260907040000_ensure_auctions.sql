-- =============================================================================
-- Migration: 20260907040000_ensure_auctions.sql
-- Description: Ensures all products with listing_type = 'auction' have a
--              corresponding row in public.auctions, backfills missing records,
--              and attaches a database trigger for future inserts/updates.
-- =============================================================================

-- 1. Function to auto-create an auction record if missing for an auction product
CREATE OR REPLACE FUNCTION public.handle_product_auction_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If product is an auction, make sure an active auction record exists
  IF NEW.listing_type = 'auction' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.auctions WHERE product_id = NEW.product_id
    ) THEN
      INSERT INTO public.auctions (
        product_id,
        starting_price,
        minimum_increment,
        current_price,
        starts_at,
        ends_at,
        status
      ) VALUES (
        NEW.product_id,
        COALESCE(NEW.price, 100),
        20,
        COALESCE(NEW.price, 100),
        COALESCE(NEW.created_at, now()),
        COALESCE(NEW.created_at, now()) + INTERVAL '3 days',
        'active'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 2. Trigger on products table for inserts and updates
DROP TRIGGER IF EXISTS trg_products_auction_sync ON public.products;
CREATE TRIGGER trg_products_auction_sync
  AFTER INSERT OR UPDATE OF listing_type, price
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_product_auction_sync();

-- 3. Backfill any existing products with listing_type = 'auction' that have no auction record
INSERT INTO public.auctions (
  product_id,
  starting_price,
  minimum_increment,
  current_price,
  starts_at,
  ends_at,
  status
)
SELECT
  p.product_id,
  COALESCE(p.price, 100),
  20,
  COALESCE(p.price, 100),
  COALESCE(p.created_at, now()),
  COALESCE(p.created_at, now()) + INTERVAL '3 days',
  'active'
FROM public.products p
LEFT JOIN public.auctions a ON a.product_id = p.product_id
WHERE p.listing_type = 'auction'
  AND a.auction_id IS NULL;
