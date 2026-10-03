-- Prevent sellers from clearing required shop address fields on their profile.

CREATE OR REPLACE FUNCTION public.enforce_seller_profiles_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.role() = 'service_role' OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.seller_id IS DISTINCT FROM OLD.seller_id THEN
    RAISE EXCEPTION 'seller_id is immutable' USING ERRCODE = '42501';
  END IF;
  NEW.is_approved := OLD.is_approved;
  NEW.approved_at := OLD.approved_at;
  NEW.total_sales := OLD.total_sales;
  NEW.follower_count := OLD.follower_count;
  NEW.created_at := OLD.created_at;

  IF NEW.shop_address IS NULL OR btrim(NEW.shop_address) = '' THEN
    RAISE EXCEPTION 'Shop address is required.' USING ERRCODE = '23514';
  END IF;
  IF NEW.barangay IS NULL OR btrim(NEW.barangay) = '' THEN
    RAISE EXCEPTION 'Barangay is required.' USING ERRCODE = '23514';
  END IF;
  IF NEW.city IS NULL OR btrim(NEW.city) = '' THEN
    NEW.city := 'Davao City';
  END IF;
  IF NEW.shop_name IS NULL OR char_length(btrim(NEW.shop_name)) < 2 THEN
    RAISE EXCEPTION 'Shop name must be at least 2 characters.' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE DELETE ON public.seller_profiles FROM authenticated;
REVOKE DELETE ON public.seller_profiles FROM anon;
