-- ThriftLine — Phase 0 behavioural RLS test (step 2 of 2: run).
--
-- Run phase0_rls_test.sql first; this file only calls what that one defines.
-- They are separate because the Supabase SQL Editor parses a whole script before
-- executing it, so a call to a function created earlier in the same run fails at
-- parse time with "function does not exist".
--
-- Expect 19 rows, all PASS.
--
--   SKIP appears only on check 12 before supabase/seed/001_role_assignments.sql
--        has been applied, when there is no admin account to impersonate.
--   FAIL means a policy does not do what its name claims. The seq numbers map to
--        the commented checks in phase0_rls_test.sql.
--
-- Safe to re-run: the function rolls back everything it writes.

SELECT * FROM public.phase0_rls_test();

-- Once Phase 0 is signed off, remove the helper:
--   DROP FUNCTION public.phase0_rls_test();
