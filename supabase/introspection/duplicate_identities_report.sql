-- Read-only report. Does not delete or merge accounts.
-- Run in the SQL Editor after applying
-- 20260905020000_prevent_cross_provider_identity_link.sql

-- 1. Trigger is installed
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM pg_trigger
      WHERE tgname = 'trg_prevent_cross_provider_identity_link'
        AND NOT tgisinternal
    )
    THEN 'PASS'
    ELSE 'FAIL'
  END AS identity_link_trigger;

-- 2. Same email on more than one auth.users row (should be 0; email is unique)
SELECT email, COUNT(*) AS auth_user_count
FROM auth.users
WHERE email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1;

-- 3. Auth users that already have more than one identity
--    (legacy auto-link from Google → email/password signup). Do not delete here.
SELECT
  u.id AS user_id,
  u.email,
  ARRAY_AGG(i.provider ORDER BY i.provider) AS providers,
  COUNT(*) AS identity_count
FROM auth.users u
JOIN auth.identities i ON i.user_id = u.id
GROUP BY u.id, u.email
HAVING COUNT(*) > 1
ORDER BY u.email;

-- 4. public.users rows that do not match exactly one auth.users id
SELECT p.user_id, p.email
FROM public.users p
LEFT JOIN auth.users u ON u.id = p.user_id
WHERE u.id IS NULL;
