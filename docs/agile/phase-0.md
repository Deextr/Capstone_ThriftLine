# Phase 0 — Backend Foundation and Database Security

**Status:** Complete  
**Goal:** Set up a secure Supabase/PostgreSQL base before building app features.

---

## What We Did

Phase 0 focused on fixing security problems and making the database ready for real backend work. No new app screens were built. Most work was in Supabase migrations, RLS policies, and small Flutter auth fixes.

---

## Main Deliverables

### 1. Database Migrations (6 files)

Applied in order in Supabase SQL Editor:

| Migration | What it does |
| --- | --- |
| `20260818010000_auth_helper_functions.sql` | Hardens `is_admin()` and adds `is_approved_seller()` |
| `20260818020000_users_integrity_and_column_guard.sql` | Fixes seller role backfill, sets default trust score, blocks users from changing their own role/trust score |
| `20260818030000_seed_categories.sql` | Seeds product categories (Tops, Bottoms, Dresses, etc.) |
| `20260818040000_rls_policy_hardening.sql` | Fixes weak RLS policies on `users`, `products`, `product_images`, `categories` |
| `20260818050000_handle_new_user_hardening.sql` | Improves signup trigger so new users always get a profile row |
| `20260818060000_users_auth_fk.sql` | Links `public.users` to `auth.users` and removes orphan profile rows |

### 2. Security Fixes

- **Stopped role self-promotion** — users can no longer change their own `role`, `trust_score`, or `account_status` from the app
- **Closed data leak** — old policy exposed all user emails/phones to anyone with the anon key
- **Added `user_public_profiles` view** — safe public user info for username checks and profile display
- **Gated product creation** — only approved sellers (and admins) can create listings
- **Server-side profile creation** — new users are created by database trigger, not by Flutter

### 3. Flutter Changes

| File | Change |
| --- | --- |
| `auth_service.dart` | Removed client-side `users` insert; only refreshes avatar on login |
| `auth_provider.dart` | Stops sending `role`, `trust_score`, `rating_average` on profile update |
| `supabase_service.dart` | Username check now uses `user_public_profiles` view |
| `enums.dart` | `ProductStatus` aligned with database (`removed` instead of `paused`) |

### 4. Seed Accounts

Created demo accounts for testing:

- 1 **admin** — approve sellers, handle reports (Studio + seed script)
- 1 **seller** — test listing creation
- 1 **buyer** — test buyer flows

Script: `supabase/seed/001_role_assignments.sql`

---

## Testing and Verification

| Test | Result |
| --- | --- |
| `phase0_verify.sql` (22 structural checks) | All PASS |
| `phase0_rls_test.sql` + `phase0_rls_run.sql` (19 behaviour checks) | All PASS |
| Google sign-up in app | Works |
| Email/password sign-up in app | Works (after disabling Confirm email in Supabase) |
| `flutter test` | 15/15 passed |

---

## Problems Found and Fixed

| Problem | Fix |
| --- | --- |
| Client could write `role` and `trust_score` | Column guard trigger + Flutter update |
| All user data readable by anon key | New RLS policies + public profile view |
| Signup could fail on username collision | Hardened `handle_new_auth_user` trigger |
| Orphan `public.users` row with no auth account | FK to `auth.users` + cleanup |
| No admin account to test moderation | Seed script for role assignment |

---

## Known Debt (Not Blocking Phase 0)

- **Email confirmation is off** — Supabase default email sender is for testing only. Need custom SMTP before deployment.
- **No admin UI yet** — admin uses Supabase Studio for now; admin logs into app as buyer home.
- **Seller listing smoke test** — recommended: log in as seeded seller and create one listing.

---

## Files Added/Updated (Reference)

```
supabase/
  migrations/          ← 6 new migration files
  seed/                ← 001_role_assignments.sql
  introspection/       ← phase0_verify.sql, phase0_rls_test.sql, phase0_rls_run.sql

lib/
  features/auth/data/auth_service.dart
  providers/auth_provider.dart
  core/services/supabase_service.dart
  models/enums.dart
```

---

## Outcome

Phase 0 is done. The database has:

- Secure RLS on core tables
- Protected user roles and trust scores
- Reliable signup → profile creation flow
- Seed accounts for buyer, seller, and admin testing

**Next:** Phase 1 — Seller verification and admin approval workflow.
