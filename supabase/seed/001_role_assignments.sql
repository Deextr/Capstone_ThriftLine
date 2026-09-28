-- ThriftLine — development role assignment.
--
-- This is SEED DATA, not a migration. It is deliberately outside
-- supabase/migrations/ because it depends on accounts that exist only in a
-- given environment, and must never run against production.
--
-- ---------------------------------------------------------------------------
-- PREREQUISITE
-- ---------------------------------------------------------------------------
-- Create the admin account first in Supabase Studio (or sign up in the app):
--
--   Authentication -> Users -> Add user -> Create new user
--   Email: dexter041711@gmail.com
--   Tick "Auto Confirm User" so no email round-trip is needed.
--
-- Do NOT insert into auth.users by hand. GoTrue owns that table: passwords are
-- bcrypt hashes it generates, and several columns (aud, role, confirmation_token,
-- instance_id) must be in a shape that changes between GoTrue versions. A
-- hand-written row typically inserts fine and then fails at login.
--
-- Creating the user in Studio fires the on_auth_user_created trigger, which
-- creates the public.users profile with role 'buyer'. This script only promotes
-- it afterwards.
--
-- Passwords are intentionally absent from this file — nothing that grants access
-- belongs in version control. Set them in Studio and record them wherever your
-- team keeps credentials.
--
-- ---------------------------------------------------------------------------
-- WHY A SCRIPT IS NEEDED AT ALL
-- ---------------------------------------------------------------------------
-- Since 20260818020000, trg_users_column_guard makes `role` unwritable by
-- ordinary clients, so an account cannot promote itself and the app cannot do it
-- either. The guard bypasses when auth.uid() IS NULL — which is the case in the
-- SQL Editor — so running this here works while the same UPDATE from the app
-- would silently revert.
--
-- Idempotent: re-running changes nothing once the role is correct.

-- ---------------------------------------------------------------------------
-- Edit this address only if the admin mailbox changes.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_seed CONSTANT jsonb := '[
    {"email": "dexter041711@gmail.com", "role": "admin", "full_name": "Admin"}
  ]'::jsonb;

  v_entry    jsonb;
  v_uid      uuid;
  v_role     user_role_enum;
  v_previous user_role_enum;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS seed_results (
    email    text,
    outcome  text,
    detail   text
  ) ON COMMIT DROP;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(v_seed)
  LOOP
    v_role := (v_entry->>'role')::user_role_enum;

    SELECT a.id INTO v_uid
    FROM auth.users a
    WHERE lower(a.email) = lower(v_entry->>'email');

    IF v_uid IS NULL THEN
      INSERT INTO seed_results VALUES (
        v_entry->>'email', 'SKIPPED',
        'No auth account. Create it in Studio -> Authentication -> Add user.');
      CONTINUE;
    END IF;

    -- The profile should already exist via the signup trigger. If it does not,
    -- something is wrong with handle_new_auth_user and that is worth surfacing
    -- rather than papering over.
    IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.user_id = v_uid) THEN
      INSERT INTO seed_results VALUES (
        v_entry->>'email', 'ERROR',
        'auth account exists but public.users row is missing — handle_new_auth_user did not fire.');
      CONTINUE;
    END IF;

    SELECT u.role INTO v_previous FROM public.users u WHERE u.user_id = v_uid;

    UPDATE public.users u
    SET    role      = v_role,
           full_name = COALESCE(NULLIF(TRIM(u.full_name), ''), v_entry->>'full_name')
    WHERE  u.user_id = v_uid;

    INSERT INTO seed_results VALUES (
      v_entry->>'email',
      CASE WHEN v_previous = v_role THEN 'UNCHANGED' ELSE 'PROMOTED' END,
      v_previous::text || ' -> ' || v_role::text);
  END LOOP;
END;
$$;

SELECT * FROM seed_results ORDER BY email;

-- ---------------------------------------------------------------------------
-- Confirm the result. Until an admin row exists, is_admin() returns false for
-- every account and every admin-only policy in the database is unreachable.
-- ---------------------------------------------------------------------------

SELECT u.username, u.full_name, u.role, u.account_status, u.trust_score
FROM public.users u
WHERE lower(u.email) = 'dexter041711@gmail.com'
   OR u.role = 'admin'::user_role_enum
ORDER BY u.role, u.username;
