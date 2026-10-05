-- Normalized lookup for "verified phone owned by another account" (OTP send/verify).

CREATE OR REPLACE FUNCTION public.is_phone_verified_by_other_user(
  p_phone text,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id IS DISTINCT FROM p_user_id
      AND COALESCE(u.is_phone_verified, false)
      AND public.normalize_ph_mobile_storage(u.phone_number)
        IS NOT DISTINCT FROM public.normalize_ph_mobile_storage(p_phone)
      AND public.normalize_ph_mobile_storage(p_phone) IS NOT NULL
  );
$$;

COMMENT ON FUNCTION public.is_phone_verified_by_other_user(text, uuid) IS
  'True when another account already verified the same canonical mobile.';

REVOKE ALL ON FUNCTION public.is_phone_verified_by_other_user(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_phone_verified_by_other_user(text, uuid) TO service_role;
