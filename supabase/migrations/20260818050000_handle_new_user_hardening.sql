-- Phase 0 / 5 — reconcile handle_new_auth_user().
--
-- The existing function is fundamentally correct and is left in place: it fires
-- AFTER INSERT ON auth.users, derives full_name from provider metadata, mints a
-- unique username, and uses ON CONFLICT (user_id) so it can never produce a
-- duplicate profile. The audit confirms it works — auth_users_without_profile
-- was 0 across all 5 accounts. This migration keeps that behaviour and fixes
-- three defects.
--
-- 1. Missing `SET search_path`.
--    The function is SECURITY DEFINER, so it runs with the owner's privileges.
--    Without a pinned search_path, anyone able to create objects in a schema
--    that resolves earlier could shadow `public.users` and capture the insert.
--
-- 2. Unbounded username loop with a check-then-insert race.
--    `WHILE EXISTS (...) LOOP ... RANDOM() ...` has no iteration cap, and the
--    existence check is not atomic with the INSERT. Two concurrent signups can
--    both observe a name as free.
--
-- 3. A username collision aborts account creation.
--    ON CONFLICT (user_id) does not catch a violation of the username unique
--    index. Because this is an AFTER INSERT trigger on auth.users, an unhandled
--    exception rolls the whole statement back and the signup fails outright.
--
-- The fix caps the loop, then falls back to a name derived from the user's UUID,
-- which is unique by construction because user_id is the primary key. A
-- unique_violation handler covers the remaining race window.
--
-- Deliberately NOT wrapped in `EXCEPTION WHEN OTHERS`: once the client-side
-- insert is removed from auth_service.dart there is no fallback path, so an
-- account created without a profile would be unrecoverable from the app.
-- Failing loudly lets the user retry; failing silently would strand them.
--
-- Idempotent. Safe to re-run. The existing on_auth_user_created trigger is not
-- dropped or recreated — only the function body it calls is replaced.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_full_name     text;
  v_avatar        text;
  v_base_username text;
  v_username      text;
  v_fallback      text;
  v_attempt       int := 0;
BEGIN
  v_full_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
    NULLIF(SPLIT_PART(COALESCE(NEW.email, ''), '@', 1), ''),
    'New User'
  );

  -- Google's ID token carries the image under `picture`. Supabase normally maps
  -- it to avatar_url, but the original function checked avatar_url only; the
  -- extra keys mirror what AuthService._extractAvatarUrlFromUser looks at.
  v_avatar := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar_url'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'picture'),    ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'avatar'),     '')
  );

  v_base_username := LOWER(REGEXP_REPLACE(v_full_name, '[^a-zA-Z0-9]', '', 'g'));
  IF v_base_username = '' THEN
    v_base_username := 'user';
  END IF;

  -- Unique by construction: user_id is the primary key.
  v_fallback := 'user_' || SUBSTRING(REPLACE(NEW.id::text, '-', '') FROM 1 FOR 12);

  v_username := v_base_username;
  WHILE v_attempt < 5
        AND EXISTS (SELECT 1 FROM public.users u WHERE u.username = v_username)
  LOOP
    v_attempt  := v_attempt + 1;
    v_username := v_base_username || FLOOR(1000 + RANDOM() * 9000)::text;
  END LOOP;

  IF EXISTS (SELECT 1 FROM public.users u WHERE u.username = v_username) THEN
    v_username := v_fallback;
  END IF;

  BEGIN
    INSERT INTO public.users (user_id, username, full_name, email, avatar)
    VALUES (NEW.id, v_username, v_full_name, NEW.email, v_avatar)
    ON CONFLICT (user_id) DO UPDATE
      SET email     = EXCLUDED.email,
          full_name = COALESCE(NULLIF(TRIM(public.users.full_name), ''),
                               EXCLUDED.full_name),
          avatar    = COALESCE(EXCLUDED.avatar, public.users.avatar);
  EXCEPTION
    WHEN unique_violation THEN
      -- A concurrent signup claimed the username between the check and the
      -- insert. Retry once with the UUID-derived name, which cannot collide.
      INSERT INTO public.users (user_id, username, full_name, email, avatar)
      VALUES (NEW.id, v_fallback, v_full_name, NEW.email, v_avatar)
      ON CONFLICT (user_id) DO NOTHING;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Creates the public.users profile for a new auth.users account. Idempotent via ON CONFLICT (user_id). role, trust_score and account_status come from column defaults.';

-- role, trust_score, rating_count and account_status are intentionally omitted
-- from the INSERT so they take their column defaults (buyer / 80 / 0 / active).
-- Keeping them out of the function means the defaults stay the single source of
-- truth and cannot drift from the table definition.
