-- Prevent authenticated clients from changing phone_number while is_phone_verified
-- stays true. OTP verification (service_role) remains the only way to set a new
-- verified mobile number.

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('thriftline.maintain_trust', true) IS DISTINCT FROM '1' THEN
    NEW.trust_score      := OLD.trust_score;
    NEW.trust_level      := OLD.trust_level;
    NEW.trust_breakdown  := OLD.trust_breakdown;
    NEW.trust_updated_at := OLD.trust_updated_at;
  END IF;

  IF auth.uid() IS NULL OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF COALESCE(OLD.is_phone_verified, false)
     AND NEW.phone_number IS DISTINCT FROM OLD.phone_number
     AND NOT public.is_admin() THEN
    NEW.phone_number := OLD.phone_number;
  END IF;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSIF public.is_admin()
          AND current_setting('thriftline.seller_promotion', true) = '1'
          AND OLD.role = 'buyer'::public.user_role_enum
          AND NEW.role = 'seller'::public.user_role_enum THEN
      NULL;
    ELSE
      NEW.role := OLD.role;
    END IF;
  END IF;

  IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
    IF OLD.account_status = 'banned'::public.account_status_enum THEN
      RAISE EXCEPTION
        'banned accounts cannot be reactivated through user management'
        USING ERRCODE = '42501';
    END IF;

    IF OLD.role IN (
         'buyer'::public.user_role_enum,
         'seller'::public.user_role_enum
       )
       AND NEW.role IN (
         'buyer'::public.user_role_enum,
         'seller'::public.user_role_enum
       ) THEN
      IF NEW.account_status IN (
        'banned'::public.account_status_enum,
        'deactivated'::public.account_status_enum
      ) THEN
        NULL;
      ELSIF OLD.account_status = 'active'::public.account_status_enum
         AND NEW.account_status = 'suspended'::public.account_status_enum
         AND current_setting('thriftline.marketplace_disable', true) = '1' THEN
        NULL;
      ELSIF OLD.account_status = 'suspended'::public.account_status_enum
         AND NEW.account_status = 'active'::public.account_status_enum
         AND current_setting('thriftline.marketplace_enable', true) = '1' THEN
        NULL;
      ELSE
        NEW.account_status := OLD.account_status;
      END IF;
    ELSIF current_setting('thriftline.admin_mgmt', true) = '1'
       AND public.is_super_admin() THEN
      NULL;
    ELSE
      NEW.account_status := OLD.account_status;
    END IF;
  END IF;

  IF OLD.role = 'super_admin'::public.user_role_enum
     AND OLD.account_status = 'active'::public.account_status_enum
     AND (
       NEW.role IS DISTINCT FROM 'super_admin'::public.user_role_enum
       OR NEW.account_status IS DISTINCT FROM 'active'::public.account_status_enum
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.users u
       WHERE u.role = 'super_admin'::public.user_role_enum
         AND u.account_status = 'active'::public.account_status_enum
         AND u.user_id <> OLD.user_id
     )
  THEN
    RAISE EXCEPTION 'the last active super admin cannot be deactivated or demoted'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Clients cannot grant admin roles or replace a verified phone without OTP (service_role). Marketplace disable/enable require RPC session flags.';

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

COMMENT ON FUNCTION public.user_has_verified_account_phone(uuid) IS
  'True when the user row has is_phone_verified and a normalized 09XXXXXXXXX phone_number.';
