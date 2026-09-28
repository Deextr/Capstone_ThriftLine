-- Phase 0 / 2 of 4 — public.users integrity and privilege-escalation guard.
--
-- Closes the most serious finding in the Phase 0 audit: the `users_update_self_admin`
-- policy grants UPDATE on the whole row to its owner, so a signed-in user could
-- set their own `role` to 'seller' or their own `trust_score` to 100. The Flutter
-- app actually does this today — AuthProvider.simulateApproveApplication() sends
-- role: 'seller' through updateCurrentUser().
--
-- Postgres has no column-level RLS, so a BEFORE UPDATE trigger is the correct
-- mechanism for making individual columns unwritable.
--
-- Idempotent. Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Backfill: promote existing product owners to seller.
-- ---------------------------------------------------------------------------
-- Must run BEFORE the guard trigger exists, and before the RLS migration starts
-- gating product INSERT on is_approved_seller(). The audit shows 4 products but
-- only 1 user with role='seller', so at least one product owner is still a buyer
-- and would otherwise lose the ability to create listings.

UPDATE public.users u
SET    role = 'seller'::user_role_enum
WHERE  u.role = 'buyer'::user_role_enum
  AND  EXISTS (SELECT 1 FROM public.products p WHERE p.seller_id = u.user_id);

-- ---------------------------------------------------------------------------
-- 2. trust_score baseline.
-- ---------------------------------------------------------------------------
-- The column defaults to 0, but AuthUser.trustClassification treats anything
-- below 40 as 'Banned' — so every account created so far displays as banned.
-- 80 matches the value the Flutter client was inserting and the AuthUser
-- fallback. These are placeholder values either way; Phase 9 replaces them with
-- real Weighted Sum Model output.

ALTER TABLE public.users ALTER COLUMN trust_score SET DEFAULT 80;

UPDATE public.users SET trust_score = 80 WHERE trust_score = 0;

-- ---------------------------------------------------------------------------
-- 3. Missing updated_at trigger.
-- ---------------------------------------------------------------------------
-- Every other table has trg_<table>_updated_at; public.users was skipped, which
-- is why the Flutter client hand-sets updated_at on every profile write.

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Column guard.
-- ---------------------------------------------------------------------------
-- Reverts protected columns to their previous values instead of raising. This
-- is deliberate: migrations land before app rebuilds, and the currently shipped
-- Flutter build sends role / trust_score / rating_average on every profile save.
-- Raising would turn every "Save Profile" tap into an error for users on the old
-- build. Reverting makes the columns inert immediately while the client catches
-- up, which is the safer ordering.
--
-- Bypasses:
--   auth.uid() IS NULL  -> no JWT, i.e. a migration, the SQL editor, or a
--                          service-role job. Safe because the RLS policy
--                          (auth.uid() = user_id OR is_admin()) already matches
--                          zero rows for an anonymous client, so this branch is
--                          unreachable from the app.
--   service_role        -> trusted server-side context.
--   is_admin()          -> admins legitimately change role and account_status.

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

  NEW.role           := OLD.role;
  NEW.trust_score    := OLD.trust_score;
  NEW.rating_average := OLD.rating_average;
  NEW.rating_count   := OLD.rating_count;
  NEW.account_status := OLD.account_status;
  NEW.created_at     := OLD.created_at;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Makes role, trust_score, rating_average, rating_count, account_status and created_at unwritable by ordinary clients.';

DROP TRIGGER IF EXISTS trg_users_column_guard ON public.users;

CREATE TRIGGER trg_users_column_guard
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.enforce_users_column_guard();

-- ---------------------------------------------------------------------------
-- 5. Stop public.users generating its own identifiers.
-- ---------------------------------------------------------------------------
-- user_id defaults to gen_random_uuid(), which lets a row be created that
-- corresponds to no auth.users account. The audit found exactly one such orphan
-- (profiles_without_auth_user = 1). The primary key must always be supplied by
-- handle_new_auth_user() from auth.users.id.
--
-- The matching FOREIGN KEY to auth.users(id) is intentionally NOT added here —
-- it would fail while that orphan row exists. See migration 20260818050000.

ALTER TABLE public.users ALTER COLUMN user_id DROP DEFAULT;
