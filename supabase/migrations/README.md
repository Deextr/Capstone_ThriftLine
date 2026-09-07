# ThriftLine database migrations

Migrations are named `<UTC timestamp>_<description>.sql` and must be applied in
filename order. Every file is idempotent, so re-running one is harmless.

The Supabase CLI is not installed on this project yet, so migrations are applied
by pasting each file into the Supabase SQL Editor in order. Once the CLI is set
up, `supabase db push` will pick up the same directory unchanged.

## Phase 0 — foundation and database security

| File | Purpose |
| --- | --- |
| `20260818010000_auth_helper_functions.sql` | Hardens `is_admin()`, adds `is_approved_seller()` |
| `20260818020000_users_integrity_and_column_guard.sql` | Seller backfill, trust score baseline, `updated_at` trigger, column guard preventing role/trust self-escalation |
| `20260818030000_seed_categories.sql` | Adds the Vintage / Streetwear / Formal categories |
| `20260818040000_rls_policy_hardening.sql` | Removes duplicate and over-permissive policies on the four core tables, adds `user_public_profiles` |
| `20260818050000_handle_new_user_hardening.sql` | Pins `search_path`, bounds the username loop, stops a collision from aborting signup |
| `20260818060000_users_auth_fk.sql` | Deletes the orphaned profile, adds the `users -> auth.users` foreign key |

`20260818060000` contains the only destructive statement in Phase 0. Read its
header before applying.

Run `../introspection/phase0_verify.sql` afterwards; all 22 checks should report
`PASS`.

## Phase 1 — seller identity, admin review, OTP, notifications

| File | Purpose |
| --- | --- |
| `20260822010000_users_identity_columns.sql` | `bio`, `location`, `is_phone_verified`; clients cannot write the verified flag |
| `20260822020000_seller_profiles.sql` | 1:1 shop profile; existing sellers backfilled as approved |
| `20260822030000_user_verifications_revision.sql` | Shop fields, liveness, pending-only insert |
| `20260822040000_verification_storage.sql` | Private `verification-docs` bucket |
| `20260822050000_user_settings.sql` | Per-user notification preferences |
| `20260822060000_addresses_rls.sql` | Owner-only addresses, one default |
| `20260822070000_notifications.sql` | Server-written inbox + Realtime |
| `20260822080000_verification_approval.sql` | Approval trigger and admin RPC |
| `20260822090000_phone_otp_challenges.sql` | OTP rows visible only to service_role |

Run `../introspection/phase1_verify.sql` afterwards; all 13 checks should report
`PASS`.

Edge Functions live in `../functions/send-phone-otp` and
`../functions/verify-phone-otp`. Deploy them and set `FMCSMS_API_KEY` plus
`OTP_PEPPER` before testing SMS. The Flutter app must never receive those values.

## Email OTP (signup and login)

| File | Purpose |
| --- | --- |
| `20260905010000_email_otp_challenges.sql` | Email OTP challenge table with **no client RLS** |

Edge Functions live in `../functions/send-email-otp` and
`../functions/verify-email-otp`. Deploy them and set `GMAIL_USER`,
`GMAIL_APP_PASSWORD`, and `OTP_PEPPER`. Keep Auth "Confirm email" off so
signup returns a session before the OTP screen. See `../../docs/agile/email-otp.md`.

## Seed data

`../seed/` holds environment-specific data that is deliberately not part of the
migration chain, because it depends on accounts that exist only in one project.

`001_role_assignments.sql` promotes `dexter041711@gmail.com` to admin. Create
that account in Studio first — GoTrue owns `auth.users` and hand-written rows
there break at login. Passwords are never stored in this file.

## Conventions

- Authorization lives in RLS policies and `SECURITY DEFINER` helpers, never in
  the Flutter client.
- Helper functions used inside policies must be `SECURITY DEFINER` with an
  explicit `SET search_path`, otherwise a policy on `users` that calls a function
  reading `users` will recurse.
- Column-level write protection uses `BEFORE UPDATE` triggers, because Postgres
  RLS operates on rows, not columns.
