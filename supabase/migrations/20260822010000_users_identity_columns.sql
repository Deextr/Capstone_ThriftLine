-- Phase 1 — identity columns on public.users.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS location character varying(255),
  ADD COLUMN IF NOT EXISTS is_phone_verified boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_active_at timestamptz;

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR auth.role() = 'service_role'
     OR public.is_admin()
  THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.role              := OLD.role;
  NEW.trust_score       := OLD.trust_score;
  NEW.rating_average    := OLD.rating_average;
  NEW.rating_count      := OLD.rating_count;
  NEW.account_status    := OLD.account_status;
  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  RETURN NEW;
END;
$$;
