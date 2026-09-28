-- Phase 0 / 1 of 4 — authorization helper functions.
--
-- is_admin() already existed (SECURITY DEFINER, sql). This replaces it with a
-- hardened body and adds the missing is_approved_seller(). Both are referenced
-- by RLS policies, so they must exist before 20260818040000_rls_policy_hardening.
--
-- Why SECURITY DEFINER: these read public.users, and public.users has RLS.
-- An INVOKER function called from inside a users policy would re-enter that
-- policy and recurse. DEFINER executes as the function owner and bypasses RLS,
-- which breaks the cycle.
--
-- Why `set search_path`: without it, a caller can prepend a schema containing a
-- malicious `users` table and the DEFINER function would read that instead.
--
-- Idempotent. Safe to re-run.

-- ---------------------------------------------------------------------------
-- is_admin()
-- ---------------------------------------------------------------------------
-- Behaviour change vs the previous definition: an admin whose account_status is
-- not 'active' (suspended / banned / deactivated) no longer counts as an admin.
-- Unauthenticated callers get auth.uid() = NULL, match no row, and return false.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id        = auth.uid()
      AND u.role           = 'admin'::user_role_enum
      AND u.account_status = 'active'::account_status_enum
  );
$$;

COMMENT ON FUNCTION public.is_admin() IS
  'True when the current JWT belongs to an active admin. Returns false when unauthenticated.';

-- ---------------------------------------------------------------------------
-- is_approved_seller()
-- ---------------------------------------------------------------------------
-- Phase 0 definition: role is seller (or admin, so support staff can act) and
-- the account is active.
--
-- This is only meaningful because 20260818020000 installs a column guard that
-- stops users from writing their own `role`. Before that guard, any user could
-- self-promote to seller by calling updateCurrentUser() from the app.
--
-- PHASE 1 TODO: tighten to additionally require an approved verification, i.e.
--   AND EXISTS (SELECT 1 FROM public.user_verifications v
--               WHERE v.user_id = u.user_id
--                 AND v.verification_status = 'approved')
-- It is deliberately NOT required yet: no account has ever completed real
-- verification (approval is currently a simulated button in the Flutter app),
-- so requiring it today would lock every existing seller out of Add Listing.

CREATE OR REPLACE FUNCTION public.is_approved_seller()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id        = auth.uid()
      AND u.role           IN ('seller'::user_role_enum, 'admin'::user_role_enum)
      AND u.account_status = 'active'::account_status_enum
  );
$$;

COMMENT ON FUNCTION public.is_approved_seller() IS
  'True when the current JWT belongs to an active seller or admin. Phase 1 will also require an approved user_verifications row.';

GRANT EXECUTE ON FUNCTION public.is_admin()            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_approved_seller()  TO anon, authenticated;
