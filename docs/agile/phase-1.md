# Phase 1 — Seller Identity, Admin Review, OTP, and Notifications

**Status:** Code complete — apply SQL, deploy Edge Functions, then test  
**Goal:** Real seller verification, in-app admin approval, Philippine SMS OTP, and live notifications. Catalog, bidding, chat, and payments stay out of scope.

---

## What We Did

Phase 1 turns Become a Seller into a real application: government ID upload, live face check, admin review in the app, and SMS OTP via iProgSMS. The Flutter client never sees the SMS API token or the OTP hash.

---

## Main Deliverables

### 1. Database Migrations (9 files)

Apply **in filename order** in the Supabase SQL Editor after Phase 0:

| Migration | What it does |
| --- | --- |
| `20260822010000_users_identity_columns.sql` | Adds `bio`, `location`, `is_phone_verified`; blocks clients from writing `is_phone_verified` |
| `20260822020000_seller_profiles.sql` | Shop profile table; backfills existing sellers as approved |
| `20260822030000_user_verifications_revision.sql` | Shop fields, liveness result, pending-only insert, one pending application per user |
| `20260822040000_verification_storage.sql` | Private `verification-docs` bucket + storage RLS |
| `20260822050000_user_settings.sql` | Notification/language preferences |
| `20260822060000_addresses_rls.sql` | Owner-only addresses; one default per user |
| `20260822070000_notifications.sql` | Server-written notifications + Realtime |
| `20260822080000_verification_approval.sql` | Approval trigger, `review_seller_verification()` for in-app admins |
| `20260822090000_phone_otp_challenges.sql` | OTP challenge table with **no client RLS** |

### 2. Edge Functions

| Function | Purpose |
| --- | --- |
| `send-phone-otp` | Creates a hashed 6-digit code and sends it through FMCSMS |
| `verify-phone-otp` | Checks the code and sets `users.is_phone_verified` |

### 3. Flutter

- Become a Seller uploads a real ID and runs look-left / look-right / blink liveness
- Fake Approve/Reject simulator is gone
- Admin home (`/admin`) lists pending applications and shows signed ID + face photos
- Settings, address book, and phone verification persist to Supabase
- Notification inbox and home badge use the `notifications` table + Realtime

---

## What You Still Need To Do For OTP

The app code is ready. SMS will fail until these steps are done **outside Flutter**.

### A. FMCSMS account

1. Sign in at [https://www.fortmed.org/web/FMCSMS/auth/login.php](https://www.fortmed.org/web/FMCSMS/auth/login.php).
2. Request an **API key** from the dashboard. Their admin team must approve it before sends work.
3. Use the 10 free SMS or buy a credit pack.
4. Copy the approved API key. Do **not** put it in `.env` or any Dart file.
5. In the dashboard API docs, confirm the four POST fields. The function sends `api_key`, `number`, `message`, and `sender`.

### B. Apply the Phase 1 SQL

In Supabase → SQL Editor, run the nine files above in order. Then run `supabase/introspection/phase1_verify.sql`. Every row should say `PASS`.

### C. Deploy the two Edge Functions

From a machine with the Supabase CLI logged in:

```bash
supabase functions deploy send-phone-otp
supabase functions deploy verify-phone-otp
```

Or create both functions in the Dashboard and paste the files from `supabase/functions/`.

### D. Set function secrets

In Supabase → Edge Functions → Secrets (or `supabase secrets set`):

| Secret | Value |
| --- | --- |
| `FMCSMS_API_KEY` | Approved API key from the FMCSMS dashboard |
| `OTP_PEPPER` | A long random string you invent (not the SMS key) |
| `FMCSMS_API_URL` | Optional. Default is `https://www.fortmed.org/web/FMCSMS/api/messages.php` |
| `FMCSMS_SENDER` | Optional. Default is `ThriftLine` |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are already available inside Edge Functions. Do not copy the service role key into Flutter.

### E. Test with real numbers

1. Sign in on a phone.
2. Settings → Phone number → send a code to a Globe number and a Smart number.
3. Confirm the SMS arrives and the 6-digit code marks the account verified.
4. If the function returns a field-name error, copy the sample request from the FMCSMS dashboard and we will match it.

---

## How To Test The Rest Of Phase 1

1. Sign in as a **buyer**. Become a Seller → pick a real ID photo → complete look left/right/blink → submit.
2. Confirm the buyer sees “under review” and gets an in-app notification.
3. Sign in as the **seeded admin**. Home should be Seller reviews. Open the application, inspect ID + face photo, approve or reject with a reason.
4. After approve, reload the buyer: role becomes seller and listing tools unlock.
5. After reject, the buyer can reapply (a new pending row is allowed).
6. Add a default address and confirm Payment & Delivery uses it.

---

## Security Rules Kept

- Sellers cannot self-approve (`review_seller_verification` is admin-only; column guard blocks status writes)
- Verification images stay in a private bucket; admins get short-lived signed URLs
- Clients cannot insert notifications
- Clients cannot write `is_phone_verified`
- iProgSMS token and OTP hash never leave the server

---

## Known Debt (Not Blocking Phase 1)

- Email confirmation / custom SMTP is still off (Phase 0 debt)
- Push device tokens are not wired; the settings toggle only stores preference
- Catalog, bidding, chat, payments, shipping, reviews, and trust-score WSM stay for later phases

---

## Outcome

When SQL + functions + iProg secrets are in place, Phase 1 is done. **Stop and get approval before Phase 2.**
