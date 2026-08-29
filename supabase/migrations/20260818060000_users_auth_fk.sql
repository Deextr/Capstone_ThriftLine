-- Phase 0 / 6 — bind public.users to auth.users.
--
-- public.users has no foreign key to auth.users. Combined with the
-- gen_random_uuid() default on its primary key (dropped in 20260818020000),
-- nothing prevented a profile row from existing with no corresponding account.
-- The audit found exactly one such row.
--
-- DESTRUCTIVE STEP — read before applying.
--
-- Step 1 deletes orphaned profiles. The follow-up probe identified a single
-- orphan and confirmed it is referenced by nothing:
--
--   user_id         5f894e5e-405e-4b64-af9c-a0e3f4ff94c9
--   username        user_5f894e5e
--   full_name       Apolonio Ramos
--   role            buyer
--   created_at      2026-08-11
--   products 0, addresses 0, orders 0, saved_items 0, verifications 0, bids 0
--
-- Its username does not match the pattern handle_new_auth_user() generates
-- (which would have produced 'apolonioramos'), so it was not created by the
-- trigger — it predates it or was inserted by hand.
--
-- The delete is guarded by the database itself: every table referencing
-- users.user_id does so with ON DELETE RESTRICT or CASCADE, so if any row were
-- referenced after all the statement would abort and nothing would be lost.
--
-- Idempotent. Safe to re-run.

DO $$
DECLARE
  v_deleted int;
BEGIN
  DELETE FROM public.users u
  WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.user_id);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RAISE NOTICE 'Removed % orphaned profile row(s) with no auth.users account.', v_deleted;
END;
$$;

-- ON DELETE CASCADE: deleting an account removes its profile. Note this does not
-- silently destroy marketplace history — products.seller_id, orders.buyer_id and
-- orders.seller_id all reference users with ON DELETE RESTRICT, so deleting an
-- account that owns listings or orders still fails loudly, as it should.

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_user_id_fkey;

ALTER TABLE public.users
  ADD CONSTRAINT users_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT users_user_id_fkey ON public.users IS
  'Every profile must correspond to an auth.users account. Rows are created only by handle_new_auth_user().';
