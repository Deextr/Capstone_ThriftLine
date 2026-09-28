UPDATE public.addresses a
SET is_default = false
WHERE a.is_default IS TRUE
  AND a.address_id NOT IN (
    SELECT DISTINCT ON (b.user_id) b.address_id
    FROM public.addresses b
    WHERE b.is_default IS TRUE
    ORDER BY b.user_id, b.created_at ASC NULLS LAST
  );

ALTER TABLE public.addresses
  ALTER COLUMN address_id SET DEFAULT gen_random_uuid();

DROP TRIGGER IF EXISTS trg_addresses_updated_at ON public.addresses;
CREATE TRIGGER trg_addresses_updated_at
BEFORE UPDATE ON public.addresses
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.enforce_one_default_address()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.is_default IS TRUE THEN
    UPDATE public.addresses a
    SET is_default = false
    WHERE a.user_id = NEW.user_id
      AND a.address_id IS DISTINCT FROM NEW.address_id
      AND a.is_default IS TRUE;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_addresses_one_default ON public.addresses;
CREATE TRIGGER trg_addresses_one_default
BEFORE INSERT OR UPDATE OF is_default ON public.addresses
FOR EACH ROW EXECUTE FUNCTION public.enforce_one_default_address();

CREATE UNIQUE INDEX IF NOT EXISTS addresses_one_default_per_user
  ON public.addresses (user_id) WHERE is_default IS TRUE;

CREATE INDEX IF NOT EXISTS addresses_user_id_idx ON public.addresses (user_id);

ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS addresses_select_own ON public.addresses;
CREATE POLICY addresses_select_own ON public.addresses
  FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS addresses_insert_own ON public.addresses;
CREATE POLICY addresses_insert_own ON public.addresses
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS addresses_update_own ON public.addresses;
CREATE POLICY addresses_update_own ON public.addresses
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS addresses_delete_own ON public.addresses;
CREATE POLICY addresses_delete_own ON public.addresses
  FOR DELETE USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.addresses TO authenticated;
