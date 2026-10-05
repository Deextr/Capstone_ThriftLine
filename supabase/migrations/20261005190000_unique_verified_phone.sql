-- One verified Philippine mobile per ThriftLine account (canonical 09XXXXXXXXX).

CREATE OR REPLACE FUNCTION public.normalize_ph_mobile_storage(raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN raw IS NULL OR btrim(raw) = '' THEN NULL
    WHEN regexp_replace(raw, '\D', '', 'g') ~ '^63[0-9]{10}$' THEN
      '0' || substring(regexp_replace(raw, '\D', '', 'g') FROM 3 FOR 10)
    WHEN regexp_replace(raw, '\D', '', 'g') ~ '^09[0-9]{9}$' THEN
      regexp_replace(raw, '\D', '', 'g')
    WHEN regexp_replace(raw, '\D', '', 'g') ~ '^9[0-9]{9}$' THEN
      '0' || regexp_replace(raw, '\D', '', 'g')
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION public.normalize_ph_mobile_storage(text) IS
  'Canonical 09XXXXXXXXX storage form; matches Edge Function normalizePhPhone.';

-- Align stored numbers before enforcing uniqueness.
UPDATE public.users u
SET phone_number = public.normalize_ph_mobile_storage(u.phone_number)
WHERE u.phone_number IS NOT NULL
  AND public.normalize_ph_mobile_storage(u.phone_number) IS NOT NULL
  AND u.phone_number IS DISTINCT FROM public.normalize_ph_mobile_storage(u.phone_number);

-- If historical data verified the same number twice, keep the oldest account verified.
WITH ranked AS (
  SELECT
    user_id,
    row_number() OVER (
      PARTITION BY public.normalize_ph_mobile_storage(phone_number)
      ORDER BY created_at ASC, user_id ASC
    ) AS rn
  FROM public.users
  WHERE is_phone_verified
    AND public.normalize_ph_mobile_storage(phone_number) IS NOT NULL
)
UPDATE public.users u
SET is_phone_verified = false
FROM ranked r
WHERE u.user_id = r.user_id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS users_verified_phone_unique_idx
  ON public.users (public.normalize_ph_mobile_storage(phone_number))
  WHERE is_phone_verified = true
    AND public.normalize_ph_mobile_storage(phone_number) IS NOT NULL;

COMMENT ON INDEX public.users_verified_phone_unique_idx IS
  'At most one verified account per canonical mobile. Unverified rows are not constrained.';

CREATE OR REPLACE FUNCTION public.user_has_verified_account_phone(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_user_id
      AND COALESCE(u.is_phone_verified, false)
      AND public.normalize_ph_mobile_storage(u.phone_number) IS NOT NULL
  );
$$;
