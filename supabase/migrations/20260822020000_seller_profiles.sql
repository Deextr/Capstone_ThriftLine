-- Phase 1 — seller_profiles (1:1 with users, created on approval).

CREATE TABLE IF NOT EXISTS public.seller_profiles (
  seller_id      uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE CASCADE,
  shop_name      character varying(80) NOT NULL,
  shop_bio       text,
  shop_address   text,
  barangay       character varying(120),
  city           character varying(120) NOT NULL DEFAULT 'Davao City',
  is_approved    boolean NOT NULL DEFAULT false,
  approved_at    timestamptz,
  total_sales    integer NOT NULL DEFAULT 0,
  follower_count integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seller_profiles_shop_name_len CHECK (char_length(trim(shop_name)) BETWEEN 2 AND 80)
);

DROP TRIGGER IF EXISTS trg_seller_profiles_updated_at ON public.seller_profiles;
CREATE TRIGGER trg_seller_profiles_updated_at
BEFORE UPDATE ON public.seller_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.seller_profiles (seller_id, shop_name, city, is_approved, approved_at)
SELECT u.user_id,
       COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.username), ''), 'Shop'),
       'Davao City', true, now()
FROM public.users u
WHERE u.role = 'seller'::user_role_enum
ON CONFLICT (seller_id) DO NOTHING;

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
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seller_profiles_column_guard ON public.seller_profiles;
CREATE TRIGGER trg_seller_profiles_column_guard
BEFORE UPDATE ON public.seller_profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_seller_profiles_column_guard();

ALTER TABLE public.seller_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_profiles FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seller_profiles_select_visible ON public.seller_profiles;
CREATE POLICY seller_profiles_select_visible ON public.seller_profiles
  FOR SELECT USING (is_approved OR auth.uid() = seller_id OR public.is_admin());

DROP POLICY IF EXISTS seller_profiles_update_own ON public.seller_profiles;
CREATE POLICY seller_profiles_update_own ON public.seller_profiles
  FOR UPDATE
  USING (auth.uid() = seller_id OR public.is_admin())
  WITH CHECK (auth.uid() = seller_id OR public.is_admin());

GRANT SELECT, UPDATE ON public.seller_profiles TO authenticated;
GRANT SELECT ON public.seller_profiles TO anon;
