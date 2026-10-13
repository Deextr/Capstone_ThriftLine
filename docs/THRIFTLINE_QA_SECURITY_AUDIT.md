# ThriftLine QA and Security Audit

## 1. Audit Overview

| Item | Detail |
|---|---|
| **Purpose** | Practical list of confirmed bugs, security gaps, improvements, and items needing live tests—based on this repository’s source. |
| **Date** | 12 October 2026 |
| **Inspected** | Single Flutter app (buyer, seller, Admin Web Portal); `lib/features/*`; `supabase/migrations/`; Edge Functions under `supabase/functions/` |
| **Not inspected** | Live Supabase project; hosted Auth settings (JWT lifetime, password grant, captcha); PayMongo dashboard; `product-images` bucket (used in app, not defined in migrations); runtime/device tests |
| **Method** | Static review of Dart, SQL, and TypeScript. Later migrations treated as current. Unit tests read as intent only—not proof of production behavior. |
| **Limitation** | Nothing in this audit was fixed. Controls are listed as present only when verified in source. |

### Finding ID scheme

Each row in a findings table has a **unique ID**. Primary definitions live in one component section; other sections reference the same ID with a short summary (no duplicate long evidence).

| Prefix | Component |
|---|---|
| `BUY-` | Buyer mobile app (including buyer-only validation `BUY-VAL-`) |
| `SEL-` | Seller mobile app (`SEL-VAL-` for validation) |
| `ADM-` | Admin Web Portal (`ADM-VAL-` for validation) |
| `SA-` | Superadmin and admin account management |
| `AUTH-` | Authentication and account security |
| `DB-` | Supabase backend, database, storage |
| `MKT-` | Marketplace, bidding, orders, payments |
| `RATE-` | Rate limiting, spam, abuse (gaps and controls) |
| `ERR-` | Error handling, reliability, recovery |
| `XSYS-` | Cross-system integration and consistency |

### Status labels

| Status | Meaning |
|---|---|
| Confirmed bug | Incorrect or unsafe behavior verified in source |
| Confirmed security gap | Missing or bypassable protection verified in source |
| Improvement recommendation | Weaker design; limited direct harm |
| Requires verification | Hosted project, Auth, or live test still needed |

### Verified controls (do not re-file as missing)

Checkout totals, fee (2%), and shipping are computed in SQL; `create-paymongo-checkout` uses `prepare_paymongo_checkout` amounts only. Webhook requires signature; duplicate `event_key` is idempotent after insert. `orders` / `payments` are not client-writable. `place_bid` and `submit_review` enforce eligibility via RPCs. `verification-docs` is private (5 MB, path = user id). Admin roles come from `public.users`, not JWT `user_metadata`. Phone OTP uses CSPRNG, quotas, and 5 verify attempts. Password reset returns uniform `{ok:true}` and is rate-limited server-side.

---

## 2. Risk Classification Guide

| Level | Meaning | Examples in this audit |
|---|---|---|
| **Critical** | Financial loss, broken payment reconciliation, or trust in money movement fails | Capture ignored after void; auction paid webhook dropped without refund |
| **High** | Serious abuse, privilege bypass, or sensitive data exposure | API access before email OTP; seller reads PIN hash; reconcile amount retry |
| **Medium** | Wrong data, bounded abuse, client/server mismatch | Client-only field limits; idle timer without JWT revoke; forged audit rows |
| **Low** | UX, enumeration, display drift | Signup messages; shipping preview vs charge; public bid SELECT |

---

## 3. Buyer Mobile App

Buyer and seller share one Flutter app. Payment findings are defined under **Marketplace** (`MKT-*`); auth findings under **Authentication** (`AUTH-*`).

### Critical Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-001 | Critical | Checkout failure/cancel calls `void_unpaid_checkout` before PayMongo finishes; later paid webhook stored as `ignored` / `already_voided` with no refund | Buyer charged; stock restored; seller unpaid | Do not void while live `cs_` session may capture; on paid-after-void, refund + alert | Pay in test mode; trigger app failure path before webhook; check order, stock, refund | Captured payment completes order or creates refund; stock not restored on capture | Confirmed bug | `finalize_my_paymongo_checkout` in `20261007090400_payment_status_expired_not_enum.sql`; `apply_paymongo_event` in `20261007200000_checkout_listing_limit_void_overloads.sql` |

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-001 | High | Email OTP is UI-only; JWT issued before code (affects all app users) | Password + sign-in yields API access without OTP | Session only after OTP or server trusted device | Sign in, stop at OTP, call protected table with token | Denied until OTP; trusted skip on server | Confirmed security gap | `sign-in-with-email/index.ts`; `auth_provider.dart` `authIsFullyAuthenticated` |
| AUTH-002 | High | Turnstile, lockout, admin gate only on Edge Function; direct Auth password grant bypasses | Script with anon key + password skips OTP and portal lockout | Lockout/captcha on every grant or disable public password grant | After 5 portal failures, Auth password grant; admin RPC with token | Grant denied or lockout applies | Confirmed security gap | `sign-in-with-email`; `auth_service.dart` `signInWithPassword`; `config.toml` |
| MKT-003 | High | Reconcile retries `apply_paymongo_event` with DB total after amount mismatch | Undercharge can mark group paid at DB total | Remove retry; pending on mismatch/null PayMongo amount | Reconcile with wrong session amount and missing amount | Orders stay pending | Confirmed security gap | `reconcile-paymongo-checkout/index.ts` ~437–447 |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-004 | Medium | Multi-shop reconcile: `groupAlreadyPaid` true if any sibling paid | UI success while another shop still pending | Group paid only when all non-cancelled siblings paid | Two-shop checkout; one shop paid; reconcile | Not full success until all paid | Confirmed bug | `reconcile-paymongo-checkout/index.ts` `groupAlreadyPaid` |
| MKT-005 | Medium | Double Pay Now can create second PayMongo session | Untracked second charge possible | Single open session; disable Pay Now until return | Double-tap Pay Now; pay first URL after second session | One `cs_`; one charge tied to order | Confirmed security gap | `buyer_orders_controller.dart`; `create-paymongo-checkout` |
| BUY-VAL-001 | Medium | **Full name (signup):** no max length; Flutter pattern only | Oversized `users.full_name` if API write possible | 2–80 after trim; DB CHECK | 1 char and 1,000 chars on signup | Rejected before save | Confirmed security gap | `Validators.name`; no length CHECK on `users.full_name` |
| BUY-VAL-002 | Medium | **Full name (profile edit):** no max, no letter pattern | Weaker than signup; unbounded storage | Match signup rules client + DB | Symbols and 200 chars in edit profile | Same rejection as signup | Confirmed security gap | `edit_profile_form.dart` |
| BUY-VAL-003 | Medium | **Address recipient/street:** required trim only; no max | Huge address strings | Recipient 2–80; street 5–200; DB CHECK | Paste 5,000 chars | Rejected | Confirmed security gap | Buyer address forms; `addresses` columns |
| BUY-VAL-004 | Medium | **Barangay:** Flutter Davao allow-list; DB only rejects blank | API can set non-list barangay | Same allow-list in trigger | POST address with invalid barangay | Rejected | Confirmed security gap | `DavaoBarangay`; `enforce_address_davao_city` |
| BUY-VAL-005 | Medium | **Looking For title:** form non-empty only; RPC requires 3–140 | Late failure after submit | Enforce 3–140 in form | 2-char and 141-char title | Blocked before submit | Confirmed security gap | `LookingForController`; `_looking_for_validate_content` |
| BUY-VAL-006 | Medium | **Looking For description:** no form max; RPC max 2000 | Late failure | Max 2000 in form | Paste >2000 chars | Blocked before submit | Confirmed security gap | RPC in looking-for migrations |
| BUY-VAL-007 | Medium | **Looking For budget:** parse fail → 0; RPC enforces range | Negative budget until RPC | Validate min/max in form; RPC keeps rules | Negative and >10M budget | Rejected in UI | Confirmed security gap | Looking For sheet + RPC |
| BUY-VAL-008 | Medium | **Bid amount:** invalid input falls back to minimum bid | User may bid minimum unintentionally | Reject invalid input; optional max bid | Letters in field; submit | Clear error, no silent minimum | Confirmed bug | `product_detail_screen.dart`; `place_bid` |
| BUY-VAL-009 | Medium | **Chat message:** no max length; no send rate limit | Huge messages; spam | Max 2000; rate limit RPC | 100k chars; rapid sends | Rejected / throttled | Confirmed security gap | `ChatDetailController`; `messages.content` |
| BUY-VAL-010 | Medium | **Password:** min 6 client-only; Auth policy unverified | Weak passwords | Product min in Auth + Flutter | 6-char password via Auth API | Matches enforced policy | Requires verification | `Validators.password` |

Looking For create limits (verified): **5 posts / 24h**, **45s** cooldown — `looking_for_posting_block`.

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-008 | Low | Debug builds skip email OTP for non-admins (`kBypassEmailOtp`) | Debug QA does not match release | Set flag false for security QA | Debug vs release buyer login | OTP required in both | Confirmed bug | `auth_provider.dart` |
| MKT-007 | Low | Checkout preview shipping flat per seller; SQL uses listing rules | Buyer approves wrong preview total | Show RPC checkout totals | Free vs fixed-fee listing | Preview = order = PayMongo | Confirmed bug | `checkout_totals.dart`; `calculate_shop_fixed_shipping` |
| AUTH-010 | Low | Signup reveals registered email and provider type | Enumeration | One message for all existing accounts | Signup known Google vs password vs new | Indistinguishable existing | Confirmed security gap | `signup_identity.dart`; `signUpWithEmail` |
| BUY-VAL-011 | Low | **Email:** no max in buyer form; reset SQL max 320 | Inconsistent | Max 320 in form | >320 chars | Rejected | Improvement recommendation | `Validators.email` |
| BUY-VAL-012 | Low | **Search:** no box max; analytics ignores <2 or >80 | UI/perf noise | Cap search at 80 | Very long query | Capped input | Improvement recommendation | `BuyerSearchController`; `record_product_search` |
| BUY-VAL-013 | Low | **Review text/rating/report details:** aligned with RPC on reports/reviews | — | Keep; match counters to RPC | Boundary 9/10 chars on reports | Matches server | Verified alignment | `submit_review`; report validators |

---

## 4. Seller Mobile App

### Critical Risk

No seller-only critical finding. Sellers are affected by **MKT-001** and **MKT-002** (payment capture ignored).

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SEL-001 | High | Seller can `SELECT delivery_pin_hash` on own shipment | Offline brute force bypasses 5-attempt PIN lock | Revoke column from `authenticated` or move hash | Seller selects hash; buyer `get_my_delivery_pin`; seller verifies PIN | Hash select fails; PIN flow unchanged | Confirmed security gap | `20261003193000_shipments_authenticated_select.sql`; Phase 7 PIN in `20260912030000_phase7_delivery.sql` |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SEL-002 | Medium | **Listing price/name/description/stock:** validated in app only; checkout trusts `products.price` | Zero/negative price, huge text via API | DB CHECK: price > 0, name 1–100, desc 1–150, stock range | API insert price -1, 5000-char name | DB rejects; checkout blocked | Confirmed security gap | `AddListingController._validateForPost`; `products_insert_own_seller` |
| MKT-006 | Medium | `restore_product_stock` read-modify-write; duplicate failure events can double-restore | Stock > reserved | Atomic `quantity_available + n`; event key before void | Parallel failed webhook same key | Quantity restored once | Confirmed bug | `20261007200000_checkout_listing_limit_void_overloads.sql` |
| MKT-009 | Medium | Stock restore reactivates listing; skips 10-active cap | >10 active listings after failed pay | Reactivate only if under cap | 10 active; fail payment on 11th | Active count ≤ 10 | Improvement recommendation | `restore_product_stock`; `seller_max_active_listings` |
| SEL-VAL-001 | Medium | **Store name:** form no 2–80; DB `seller_profiles_shop_name_len` | Form passes 1 or 81 chars | Match 2–80 in form | 1 and 81 chars | Rejected in UI | Confirmed security gap | `SellerAddressDraft`; seller profile CHECK |
| SEL-VAL-002 | Medium | **Product name/description:** client max 100/150; DB no length | API bypass | DB CHECK + NOT NULL desc | API empty desc, 500-char name | Rejected | Confirmed security gap | Add/edit listing; `products` |
| SEL-VAL-003 | Medium | **Price/stock:** client >0 and 1–9999; DB only qty >= 0 | Negative price, stock 100000 | CHECK price > 0; stock 0–9999 | API 0, -5, 10000 stock | Rejected | Confirmed security gap | `_validateForPost`; `products_quantity_available_check` |
| SEL-VAL-004 | Medium | **Category:** required in UI; `category_id` nullable in DB | Null category via API | NOT NULL or RPC reject | Insert without category | Rejected | Confirmed security gap | Add listing; schema |
| SEL-VAL-005 | Medium | **Listing photos:** 1–3 count; JPEG upload; no client size check; **`product-images` bucket not in migrations** | Oversized/wrong type if bucket loose | 5 MB + MIME client + verify hosted bucket | 20 MB file | Rejected | Requires verification | `add_listing_controller.dart` |
| SEL-VAL-006 | Medium | **ID/selfie:** JPEG forced; no client 5 MB check before upload | Large upload until storage rejects | Pre-check 5 MB | 6 MB upload | Blocked in app | Confirmed security gap | `seller_verification_service.dart`; `verification-docs` bucket |
| SEL-VAL-007 | Medium | **Shipping fee:** >0 in UI; no DB CHECK found | Extreme fee via API | Align with checkout max | Huge fee via API | Rejected server-side | Requires verification | Listing shipping section |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SEL-VAL-008 | Low | **Shop bio:** no max | Large bios | Max ~500 | 20k chars | Rejected after fix | Improvement recommendation | `ProfileController.updateProfile` |
| SEL-VAL-009 | Low | **Saved rider fields:** limits not fully traced | — | Audit forms + RPC | Blank/long name | Requires verification | Requires verification | `saved_rider_form_fields.dart` |
| SEL-VAL-010 | Low | External sale item name 2–80 client+DB; amount bounds partly unverified on DB | — | Confirm numeric CHECK | Boundary amounts | Consistent | Requires verification | External transaction migrations |

---

## 5. Admin Web Portal

Superadmin-only items: **SA-*** section. Shared auth: **AUTH-***.

### Critical Risk

No portal-only critical finding. Highest admin exposure: **AUTH-001** + **AUTH-002** (JWT without portal OTP / lockout).

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| ADM-001 | High | `test-unisms-sms`: any `admin` (not super_admin) sends SMS to any `09` number, custom text, no rate limit | Cost, abuse, harassment | Remove prod function or super_admin + allow-list + cap | Admin calls twice; buyer/super_admin call | Buyer denied; capped sends | Confirmed security gap | `supabase/functions/test-unisms-sms/index.ts`; `config.toml` verify_jwt |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-003 | Medium | 10-minute admin idle logout is Flutter timer only | Stolen token works until JWT expiry | Global revoke on idle; short admin JWT | Two browsers; idle one 10 min; RPC on other | Both sessions dead | Confirmed security gap | `admin_portal_session_policy.dart` |
| AUTH-004 | Medium | Sign-in continues if rate-limit RPC fails | Guessing during DB outage | 503, no password grant | Sign-in without claim RPC | No session | Confirmed security gap | `sign-in-with-email` claimError handling |
| AUTH-005 | Medium | Correct non-admin password on admin portal: distinct 403; session not revoked | Oracle + orphan sessions | Same 401 as wrong password; always revoke | Buyer password on admin login | Indistinguishable errors; no session | Confirmed security gap | `sign-in-with-email` admin branch |
| DB-003 | Medium | `record_admin_audit_log` callable by any admin (not account_management) | Forged escrow/security log lines | Server-only logging in action RPCs | Admin calls `payments_escrow` log | Denied | Confirmed security gap | `20261010140100_super_admin_authorization.sql` |
| SA-001 | High | Admin delete policy affects portal admins (primary: §6) | See SA-001 in Superadmin section | See SA-001 | See SA-T001 | See SA-001 | Confirmed policy gap / Requires verification | `users_delete_admin`; see §6 |
| ADM-VAL-001 | Medium | **Create-admin full name:** min 2 only; RPC 2–80; no letter rule in form | 100-char name in UI | 2–80 + pattern like profile | 100 chars in create admin | RPC/form reject | Confirmed security gap | `admin_web_accounts_page.dart`; `begin_admin_invitation` |
| ADM-VAL-002 | Medium | **Admin password invite:** min 8; profile min 12; not in Auth/SQL | Weak admin passwords | One 12+ rule in Auth + all screens | Accept invite with 8 chars | Rejected | Confirmed bug | `admin_accept_invite_screen.dart`; `Validators.adminPassword` |
| AUTH-007 | Medium | Email OTP: no hourly/IP cap; `Math.random()`; weak verify race | Email bombing, enumeration | Match phone OTP hardening | 10 sends / 60s; parallel wrong codes | 429; challenge consumed at 5 | Confirmed security gap | `send-email-otp/index.ts`; `phone_otp.ts` |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-009 | Low | Password min 6 (buyer) vs 8 (invite) vs 12 (admin profile) | Inconsistent accounts | Single policy in Auth | 11-char admin profile change | Rejected per policy | Confirmed bug | `validators.dart`; invite screen |
| ERR-001 | Low | Job Edge Functions return raw `error.message` (also **DB-001**, **DB-005**) | Info leak | Generic client message; log server-side | Force RPC failure on job URL | No SQL in response | Confirmed security gap | `close-auctions/index.ts`; `complete-expired-inspections/index.ts` |
| ADM-VAL-003 | Low | Admin avatar: client 5 MB; bucket limit not in migrations | — | Verify hosted bucket | Oversize avatar | Rejected | Requires verification | `AdminProfileController.pickAvatar` |

---

## 6. Superadmin and Administrative Account Management

Verified controls (summary): `is_super_admin()` requires active status; `/admin/administrators` and `/admin/logs` router-gated; `invite-admin` + `_assert_super_admin_actor`; duplicate emails rejected; 7-day invite expiry; deactivate global sign-out; last super admin protected on UPDATE; audit read super_admin only.

### Critical Risk

No additional critical finding. Super admins affected by **AUTH-001**, **AUTH-002**.

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SA-001 | High | RLS `users_delete_admin` for any active admin; table DELETE privilege not revoked in repo | Delete profiles outside deactivate flow | Revoke DELETE; super_admin-only RPC | Normal admin DELETE on hosted DB | Denied | Confirmed policy gap / Requires verification | `users_delete_admin` in `20260818040000_rls_policy_hardening.sql` |

**ADM-001** does not apply to super_admin (function checks `role === admin` only).

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SA-002 | Medium | Migration bootstraps first super_admin via hardcoded email if none exists | Fresh DB + repo exposure | Remove email; out-of-band bootstrap | Migration on empty DB twice | No auto-promote second user | Confirmed security gap | `20261010140100_super_admin_authorization.sql` ~1588–1627 |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-009 | Low | Invite/password rules (see Admin) | — | See AUTH-009 | — | — | Confirmed bug | See §5 |

---

## 7. Authentication and Account Security

Primary home for **AUTH-001** through **AUTH-010** (also referenced in Buyer/Admin).

### Critical Risk

No standalone critical auth finding. **AUTH-001** + **AUTH-002** are the top auth priority (JWT before OTP; bypass Edge controls).

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-001 | High | JWT returned after password before email OTP; RLS uses `auth.uid()` only | API access without 6-digit code | No session until OTP or server trusted device | Password login; API call before OTP | Denied until verified | Confirmed security gap | `sign-in-with-email/index.ts`; `auth_provider.dart` |
| AUTH-002 | High | Turnstile, email throttle, admin lockout only on Edge Function path | Direct Auth grant bypasses controls | Same controls on all grants or disable public grant | Auth `/token` after portal lockout | Blocked | Confirmed security gap / hosted Auth Requires verification | `sign-in-with-email`; `auth_service.dart` L321 |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-003 | Medium | Admin 10-minute timeout client-only | Token outlives idle tab | Global revoke + JWT TTL | Two browsers idle test | All sessions end | Confirmed security gap | `admin_portal_session_policy.dart` |
| AUTH-004 | Medium | Rate-limit RPC error → sign-in continues | Throttle gone on outage | Fail closed 503 | Missing RPC env | No session | Confirmed security gap | `sign-in-with-email` |
| AUTH-005 | Medium | Admin portal distinguishes valid non-admin password | Enumeration; orphan session | Uniform 401 + revoke | Buyer password on admin login | Same as wrong password | Confirmed security gap | `sign-in-with-email` admin branch |
| AUTH-006 | Medium | Deactivated admin can sign in via app portal path | Consumer JWT while deactivated | Same status revoke all portals | Deactivated admin app login | No session | Confirmed security gap | `sign-in-with-email` L650–664; `sessionBlockMessage` |
| AUTH-007 | Medium | Email OTP weaker than phone OTP (RNG, caps, atomic verify) | Abuse / enumeration | Align with `phone_otp.ts` | 10 email OTP sends; parallel guesses | Hourly cap; locked challenge | Confirmed security gap | `send-email-otp`; `verify-email-otp` |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| AUTH-008 | Low | `kBypassEmailOtp` true in debug for non-admins | Misleading QA | false for security builds | Debug vs release login | OTP always | Confirmed bug | `auth_provider.dart` |
| AUTH-009 | Low | Inconsistent password minimums across screens | Weak admin passwords | Auth-enforced mins | 8-char invite; 11-char admin | One rule | Confirmed bug | `validators.dart`; invite screen |
| AUTH-010 | Low | Signup provider-specific “already registered” messages | Email/provider enumeration | Generic copy + Turnstile | Signup existing accounts | Same message | Confirmed security gap | `signup_identity.dart` |
| AUTH-011 | Low | Phone OTP `phone_already_in_use` confirms verified number on another account | Enumeration to signed-in user | Generic error optional | OTP for other user’s phone | Block without revealing owner | Confirmed security gap | `send-phone-otp` |
| AUTH-012 | Low | Email OTP failure mentions Gmail SMTP | Operational leak | Generic error | Break SMTP; send OTP | No provider in UI | Confirmed security gap | `send-email-otp` catch |
| AUTH-013 | Low | IP throttle uses `X-Forwarded-For` first hop | IP limit rotation if spoofable | Trust platform client IP only | Spoofed XFF | Requires verification | Requires verification | `phone_otp.ts` `clientIp` |
| AUTH-014 | Low | Login screen `LoginRateLimiter` in-memory only | Device-only lockout | Rely on server messages | Restart app after failures | Server still limits | Improvement recommendation | `login_rate_limiter.dart` |

---

## 8. Supabase Backend, Database, and Storage

Payment-critical SQL bugs: **MKT-001**, **MKT-002**. PIN exposure: **SEL-001**.

### Critical Risk

No additional DB-only critical row. See **MKT-001**, **MKT-002**.

Escrow/seller_payouts `USING (true)` policies are **`TO postgres` only** (verified). Service role not in Flutter client.

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| SEL-001 | High | Full table SELECT on `shipments` exposes `delivery_pin_hash` to seller | PIN lock bypass | Column-level revoke | Seller SELECT hash | Fail | Confirmed security gap | `20261003193000_shipments_authenticated_select.sql` |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| DB-001 | Medium | `close_auctions()` executable by `authenticated`; HTTP job no secret | Force post-`ends_at` settlement; error leak | Revoke execute; cron secret | Buyer RPC; open HTTP URL | Denied | Confirmed security gap | `20261010150000_auction_finalize_and_relist_sync.sql`; `close-auctions/index.ts` |
| DB-002 | Medium | `try_auto_release_escrow(uuid)` no caller check; granted to `authenticated` | Early release / disputed transition by id | Revoke client execute | Stranger calls on completed order | Denied | Confirmed security gap | `20260914010000_phase10_settlement.sql` |
| DB-003 | Medium | Admins can insert audit logs for actions they did not perform | Fake escrow/security events | Log only inside action RPCs | Admin `record_admin_audit_log` | Denied | Confirmed security gap | `record_admin_audit_log` in super_admin migration |
| DB-005 | Medium | `complete_expired_inspections` HTTP no secret; SQL granted to `authenticated` | On-demand job; error leak | Same as DB-001 pattern | HTTP without auth; buyer RPC | Unauthorized fail | Confirmed security gap | `20261007100500_...sql`; `complete-expired-inspections/index.ts` |
| DB-006 | Medium | Bid/auction write policies `WITH CHECK (true)` for PUBLIC; mitigated by revoked INSERT | Latent if GRANT added | Policies `TO postgres` only | authenticated INSERT bid | Still denied today | Improvement recommendation | `20260909030000_phase3_auctions.sql` |
| DB-007 | Medium | `review_seller_verification` skips admin check when `auth.uid()` null | Latent service misuse | Require admin for all non-service calls | Buyer RPC | Denied | Improvement recommendation | `20261010140100_super_admin_authorization.sql` |
| SA-001 | Medium | Admin delete policy (see Superadmin) | — | See SA-001 | — | — | See SA-001 | See §6 |
| SA-002 | Medium | Bootstrap email (see Superadmin) | — | See SA-002 | — | — | See SA-002 | See §6 |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| DB-004 | Low | `bids_select_all` + GRANT to `anon`: all bids public | Bidder identity public | Restrict if product requires | Anon SELECT bids | Policy matches product | Improvement recommendation | Phase 3 auctions RLS |
| DB-008 | Low | `user_public_profiles` exposes `role` for active users | Admin enumeration | Drop role from view | Anon SELECT view | No admin role field | Improvement recommendation | `20260930190000_seller_trust_wsm.sql` |
| DB-009 | Low | Audit log search ILIKE without escaping `%` `_` | Wider search results | Escape wildcards | Search with `%` | Requires verification | Improvement recommendation | `list_admin_audit_logs` |

### Storage summary

| Bucket | Public (migrations) | Limit | Write access |
|---|---|---|---|
| `verification-docs` | No | 5 MB jpeg/png/webp | Owner path; admin read/delete |
| `message-attachments` | No | 5 MB | Conversation participants |
| `looking-for` | Yes | 5 MB | Verify latest policy on hosted project |
| `review-photos` | Yes | 5 MB | Review authors |
| `report-evidence` | Private in migrations | 5 MB | Participants + admin |
| `app-links` | Public select | Per migration | No client insert confirmed |
| `product-images` | **Not in migrations** | Unknown | **Requires verification** |

---

## 9. Marketplace, Bidding, Orders, and Payments

### Critical Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-001 | Critical | Buyer void before webhook; paid ignored (see Buyer §3) | Charged buyer, cancelled order | See MKT-001 Buyer row | See BUY-T001 checklist | Refund or paid order | Confirmed bug | See §3 |
| MKT-002 | Critical | Paid auction webhook after window → `ignored` / `auction_window_closed`, no refund | Charged winner, no fulfillment | Accept in-window session or auto-refund | Pay late webhook after `payment_due_at` | Paid or refund record | Confirmed bug | `apply_paymongo_event` L518–549; 12h window migrations |

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-003 | High | Reconcile amount mismatch retry (see Buyer §3) | Wrong paid state | Remove retry | Reconcile wrong amount | Pending | Confirmed security gap | `reconcile-paymongo-checkout/index.ts` |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-004 | Medium | Partial multi-shop group reported paid | One seller unpaid in UI | All siblings paid check | Two-shop partial reconcile | Not success | Confirmed bug | `groupAlreadyPaid` |
| MKT-005 | Medium | Second PayMongo session on double Pay Now | Double charge risk | Single session | Double Pay Now | One cs_ | Confirmed security gap | `create-paymongo-checkout` |
| MKT-006 | Medium | Non-atomic stock restore | Inflated quantity | Locked increment restore | Parallel fail events | Qty once | Confirmed bug | `restore_product_stock` |
| MKT-009 | Medium | Listing cap skipped on restore | >10 active listings | Cap-aware reactivate | Fail pay at cap | ≤10 active | Improvement recommendation | `skip_seller_listing_limit` |
| SEL-002 | Medium | Client-only listing validation affects checkout price integrity | Bad prices in orders | DB constraints | API negative price checkout | Blocked | Confirmed security gap | See §4 |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| MKT-007 | Low | Shipping preview ≠ charged shipping | UX mismatch | Server totals in UI | Free vs paid shipping checkout | Match | Confirmed bug | `checkout_totals.dart` |
| MKT-008 | Low | Webhook HMAC without timestamp freshness | Limited replay window | Reject old `t`; insert key before side effects | Old timestamp replay | Rejected | Improvement recommendation | `_shared/paymongo.ts` |

**Verified protections (summary):** Server-side checkout totals; order/payment RPC-only writes; webhook signature; bid/review rules; 12h auction pay window; platform fee 2%; PIN plaintext not client-readable (hash issue **SEL-001**).

---

## 10. Rate Limiting, Spam, and Abuse Prevention

### Critical Risk

No rate-limit-specific critical finding. Financial issues: **MKT-001**, **MKT-002**.

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| RATE-001 | High | Email login throttle + admin lockout only on Edge Function (**AUTH-002**) | Bypass via Auth API | See AUTH-002 | Direct grant after lockout | Blocked | Confirmed security gap | `sign-in-with-email`; `email_login_abuse`; admin lockout SQL |
| RATE-002 | High | **AUTH-001**: OTP limits do not gate JWT already issued | OTP send limits irrelevant to API | See AUTH-001 | Token before OTP | API should fail | Confirmed security gap | Auth flow |
| ADM-001 | High | Admin SMS test unlimited (**ADM-001**) | SMS abuse | Cap/remove function | Two admin SMS calls | Rate limited | Confirmed security gap | `test-unisms-sms` |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| RATE-003 | Medium | Email OTP send: 60s resend only; no hourly/IP (**AUTH-007**) | Email flood | Hourly/IP caps | 10 sends in hour | 429 | Confirmed security gap | `send-email-otp` |
| RATE-004 | Medium | Signup: no Turnstile; enumeration messages (**AUTH-010**) | Account oracle | Login parity | Rapid signup attempts | Limited + generic | Confirmed security gap | `signup_screen` |
| RATE-005 | Medium | Chat: no message rate limit (**BUY-VAL-009**) | Spam | RPC throttle | Rapid messages | Throttled | Confirmed security gap | `messages` policies |
| RATE-006 | Medium | Throttle RPC fail-open (**AUTH-004**) | Unlimited login in outage | 503 on RPC error | Broken RPC sign-in | No session | Confirmed security gap | `sign-in-with-email` |
| RATE-007 | Medium | Client login limiter not server (**AUTH-014**) | Misleading UX | Server message primary | Restart app | Server still limits | Improvement recommendation | `login_rate_limiter.dart` |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| RATE-008 | Low | IP caps depend on forwarded headers (**AUTH-013**) | Weak IP limit | Platform IP only | Spoof XFF | Requires verification | Requires verification | `phone_otp.ts` |

### Operation limits reference (verified in source)

| Operation | Limit | Enforced where | Bypass notes |
|---|---|---|---|
| Email login | 3s cooldown; 15/h email; 40/h IP hash | SQL + `sign-in-with-email` | AUTH-002, AUTH-004 |
| Admin portal login | 5 fails → 5 min | SQL + Edge when `login_portal=admin` | AUTH-002; AUTH-005 non-admin not counted |
| Password reset | 60s; 5/h per email hash | SQL + Edge; fail closed on RPC error | Turnstile `password_reset` |
| Phone OTP | 60s; 5/h user & phone; 10/h IP; 5 verify | `phone_otp.ts` | AUTH-013 |
| Email OTP verify | 5 attempts | Edge | Race per AUTH-007 |
| Looking For create | 5/24h; 45s | `looking_for_posting_block` | RPC |
| LF reports | 10/24h; 20s; 1/post | `report_looking_for_request` | RPC |
| Community reports | 30s; 5/24h | `submit_community_report` | RPC |
| Listings | 10 active max | Trigger | MKT-009 on restore |
| Reviews | 1 per order per reviewer | `submit_review` | No time cap |
| Bids | Rules in `place_bid`; no hourly cap | RPC | Direct INSERT revoked |
| Checkout | Per-buyer advisory lock | Checkout SQL | MKT-005 separate session |

**Idempotency:** Cart checkout lock + cart delete; webhook duplicate key after insert (side effects before insert: **MKT-006**); reconcile not idempotent on mismatch (**MKT-003**).

---

## 11. Error Handling, Reliability, and Recovery

Runtime device tests not executed.

### Critical Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| ERR-002 | Critical | Payment success vs order failure not reconciled (**MKT-001**, **MKT-002**) | User sees fail; PayMongo paid | See MKT-001, MKT-002 | BUY-T001, BUY-T002 | Refund or paid | Confirmed bug | See §9 |

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| ERR-003 | High | Reconcile turns amount error into paid (**MKT-003**) | False paid state | Remove retry | BUY-T003 | Pending | Confirmed security gap | Reconcile function |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| ERR-001 | Medium | Job functions return DB `error.message` | SQL leak to caller | Generic JSON + log | Trigger failing job | No SQL in body | Confirmed security gap | `close-auctions`; `complete-expired-inspections` |
| ERR-004 | Medium | Sign-in fail-open on throttle RPC (**AUTH-004**) | Security degrades silently | 503 | AUTH-T002 | No session | Confirmed security gap | Edge function |
| ERR-005 | Medium | PayMongo session expire errors swallowed (**MKT-005**) | Two live sessions | Surface/fail second create | Double Pay Now | One session | Confirmed security gap | `create-paymongo-checkout` |
| ERR-006 | Medium | `finalize_my_paymongo_checkout` returns `success: true` for pending/auction paths | Client misreads outcome | UI must use `outcome` + order row | Auction finalize JSON | UI matches DB | Improvement recommendation | `finalize_my_paymongo_checkout` |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| ERR-007 | Low | Email OTP SMTP error detail (**AUTH-012**) | Info leak | Generic message | Broken SMTP | Generic error | Confirmed security gap | `send-email-otp` |
| ERR-008 | Low | `isSubmitting` / navigation-away reset not fully verified | Stuck UI | Device QA | Leave mid-request | Spinner clears | Requires verification | Various controllers |
| ERR-009 | Low | Realtime disconnect recovery not traced | Stale chat/notifications | Device QA | Kill network | Recovers | Requires verification | Realtime subscriptions |

---

## 12. Cross-System Integration and Data Consistency

### Critical Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| XSYS-001 | Critical | PayMongo paid vs `orders` cancelled/unpaid; no refund row (**MKT-001**, **MKT-002**) | Money/order/stock diverge | Payment + refund pipeline | BUY-T001, BUY-T002 | Consistent state | Confirmed bug | Payment SQL + webhooks |

### High Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| XSYS-002 | High | Flutter OTP gate ≠ RLS JWT trust (**AUTH-001**, **AUTH-002**) | “Signed in” definitions differ | Server session gate | AUTH-T001 | One definition | Confirmed security gap | App + Edge + RLS |
| XSYS-003 | High | Reconcile prefers DB total over PayMongo (**MKT-003**) | Provider vs DB mismatch | Strict amount match | BUY-T003 | Aligned | Confirmed security gap | Reconcile |

### Medium Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| XSYS-004 | Medium | Multi-shop partial paid vs UI (**MKT-004**) | Split checkout inconsistent | Fix group paid | BUY-T005 | All shops aligned | Confirmed bug | Reconcile |
| XSYS-005 | Medium | Deactivated admin: portal vs app (**AUTH-006**) | Role/status drift | Unified revoke | AUTH-T006 | No consumer JWT | Confirmed security gap | Sign-in paths |
| XSYS-006 | Medium | Flutter vs SQL validation (Looking For, listings, shop name) | Submit then fail / bad data | DB + form parity | BUY-VAL-*, SEL-VAL-* | Same rules | Confirmed security gap | See §3–4 |
| XSYS-007 | Medium | PIN UI lock vs seller hash read (**SEL-001**) | Delivery trust broken | Revoke hash SELECT | SEL-T001 | Lock holds | Confirmed security gap | Shipments RLS |
| XSYS-008 | Medium | Banned seller: tokens until expiry (comment in migration) | Brief access after ban | Confirm session revoke on disable | Disable seller; use old token | Requires verification | Requires verification | `20261010150000_marketplace_user_management.sql` |
| XSYS-009 | Medium | `addresses` phone CHECK `NOT VALID` | Legacy bad phones | VALIDATE CONSTRAINT | DB audit phones | Requires verification | Requires verification | `20261001120000_addresses_phone_format.sql` |

### Low Risk

| ID | Level of Risk | Problem | Impact | Recommended Fix | QA Test | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| XSYS-010 | Low | Preview shipping vs charge (**MKT-007**) | Display drift | Server totals | BUY-T006 | Match | Confirmed bug | Checkout UI |
| XSYS-011 | Low | Debug vs release OTP (**AUTH-008**) | QA false confidence | Disable bypass | AUTH-T005 | Same flow | Confirmed bug | `kBypassEmailOtp` |
| XSYS-012 | Low | Notification labels vs all DB statuses | Wrong labels | Screen-by-screen QA | Requires verification | Requires verification | Requires verification | Not fully traced |
| XSYS-013 | Low | `user_public_profiles.role` exposes staff (**DB-008**) | Staff visible | Hide role | Public profile query | Policy OK | Improvement recommendation | View definition |

---

## 13. Consolidated QA Test Checklist

**Actual result** defaults to `Not tested`. Do not mark Pass from code review alone.

| Test ID | Component | Risk Level | Test Scenario | Preconditions | Test Steps | Expected Result | Actual Result | Status | Related Finding ID |
|---|---|---|---|---|---|---|---|---|---|
| BUY-T001 | Buyer | Critical | Void vs captured payment | Buyer, seller, PayMongo test | Pay; trigger failure before webhook | Paid or refund; stock not restored wrongly | Not tested | Not tested | MKT-001 |
| BUY-T002 | Buyer | Critical | Auction pay after window | Winner, 12h window | Webhook after `payment_due_at` | Paid/fulfilled or refund | Not tested | Not tested | MKT-002 |
| BUY-T003 | Buyer | High | Reconcile amount mismatch | Pending checkout | Reconcile wrong session amount | Stays pending | Not tested | Not tested | MKT-003 |
| BUY-T004 | Buyer | Medium | Second Pay Now | Pending order | Double-tap Pay Now | One `cs_` session | Not tested | Not tested | MKT-005 |
| BUY-T005 | Buyer | Medium | Two-shop partial pay | Two sellers in cart | One shop paid; reconcile | Not full group success | Not tested | Not tested | MKT-004 |
| BUY-T006 | Buyer | Low | Shipping preview | Mixed shipping listings | Compare preview, order, PayMongo | All match | Not tested | Not tested | MKT-007 |
| BUY-T007 | Buyer | Medium | Long full name signup | Signup | 1000 chars | Rejected | Not tested | Not tested | BUY-VAL-001 |
| BUY-T008 | Buyer | Medium | Looking For bounds | Signed-in buyer | 2-char title; negative budget | Rejected in UI or clear RPC error | Not tested | Not tested | BUY-VAL-005, BUY-VAL-007 |
| BUY-T009 | Buyer | Medium | Chat length / flood | Conversation | Empty; 100k chars; rapid send | Rejected/throttled | Not tested | Not tested | BUY-VAL-009 |
| BUY-T010 | Buyer | Medium | Bid input validation | Live auction | Letters; below min; valid bid | Errors then one bid | Not tested | Not tested | BUY-VAL-008 |
| BUY-T011 | Buyer | Low | Review eligibility | Paid not completed order | Review before/after completion | Blocked until completed | Not tested | Not tested | Verified control |
| SEL-T001 | Seller | High | PIN hash not readable | Out for delivery order | Seller SELECT hash; buyer PIN | Hash denied | Not tested | Not tested | SEL-001 |
| SEL-T002 | Seller | Medium | Negative price API | Approved seller | Insert price -1; checkout | Rejected | Not tested | Not tested | SEL-002 |
| SEL-T003 | Seller | Medium | Stock 100000 | Approved seller | API stock | Rejected | Not tested | Not tested | SEL-VAL-003 |
| SEL-T004 | Seller | Medium | Name/desc API bypass | Seller token | 500-char name; empty desc | DB reject | Not tested | Not tested | SEL-VAL-002 |
| SEL-T005 | Seller | Low | Listing cap after failed pay | 10 active listings | Fail payment restore | ≤10 active | Not tested | Not tested | MKT-009 |
| SEL-T006 | Seller | Medium | ID 6 MB upload | Verification | 6 MB file | Blocked | Not tested | Not tested | SEL-VAL-006 |
| SEL-T007 | Seller | Medium | Shop name 1/81 chars | Seller profile | Submit lengths | 2–80 only | Not tested | Not tested | SEL-VAL-001 |
| SEL-T008 | Seller | High | Order/payment tamper | Buyer/seller JWT | UPDATE to paid | Permission denied | Not tested | Not tested | Verified control |
| ADM-T001 | Admin | High | SMS test abuse | Admin, buyer tokens | Admin 2 SMS; buyer call | Buyer denied; capped | Not tested | Not tested | ADM-001 |
| ADM-T002 | Admin | High | Password grant during lockout | Admin | 5 fails then Auth grant | Blocked | Not tested | Not tested | AUTH-002 |
| ADM-T003 | Admin | Medium | Idle vs second browser | Two sessions | Idle 10 min | Both logged out | Not tested | Not tested | AUTH-003 |
| ADM-T004 | Admin | Medium | Non-admin on portal | Buyer password | Admin login | Same as wrong password | Not tested | Not tested | AUTH-005 |
| ADM-T005 | Admin | Medium | Forged audit log | Normal admin | `record_admin_audit_log` | Denied | Not tested | Not tested | DB-003 |
| SA-T001 | Superadmin | High | Delete user row | Hosted grants | Admin DELETE super_admin | Denied | Not tested | Not tested | SA-001 |
| SA-T002 | Superadmin | Medium | Invite password 8 vs 12 | Pending invite | 8-char accept; 11-char profile | One admin rule | Not tested | Not tested | AUTH-009, ADM-VAL-002 |
| ADM-T006 | Admin | Low | Route guards | Various roles | Open `/admin`, `/admin/administrators`, `/admin/logs` | Correct redirects | Not tested | Not tested | Verified controls |
| AUTH-T001 | Auth | High | API before email OTP | User account | Password; stop OTP; API | Denied | Not tested | Not tested | AUTH-001 |
| AUTH-T002 | Auth | Medium | Throttle fail closed | Test env | Sign-in without RPC | 503 | Not tested | Not tested | AUTH-004 |
| AUTH-T003 | Auth | Medium | Email OTP hourly cap | Signed in | 10 sends / 60s | 429 | Not tested | Not tested | AUTH-007 |
| AUTH-T004 | Auth | Low | Signup enumeration | Known emails | Three signups | Same existing message | Not tested | Not tested | AUTH-010 |
| AUTH-T005 | Auth | Low | Debug OTP bypass | Debug/release | Buyer login | OTP both | Not tested | Not tested | AUTH-008 |
| AUTH-T006 | Auth | Medium | Deactivated admin app login | Deactivated admin | App sign-in | No session | Not tested | Not tested | AUTH-006 |
| AUTH-T007 | Auth | Low | Password reset privacy | Emails | 6 reset requests | Same body; 6th limited | Not tested | Not tested | Rate limits table |
| DB-T001 | Backend | Medium | `close_auctions` as buyer | JWT | RPC + HTTP no secret | Denied | Not tested | Not tested | DB-001 |
| DB-T002 | Backend | Medium | Escrow release stranger | Completed order | Third-user RPC | Denied | Not tested | Not tested | DB-002 |
| DB-T003 | Backend | Medium | Parallel stock restore | Qty 5, reserve 1 | Two fail events | Qty 5 | Not tested | Not tested | MKT-006 |
| DB-T004 | Backend | High | Verification doc privacy | Uploaded ID | Anon/other user access | Denied | Not tested | Not tested | Storage |
| DB-T005 | Backend | Low | Public bids | Anon key | SELECT bids | Per product decision | Not tested | Not tested | DB-004 |
| DB-T006 | Backend | Medium | Inspection job unauthorized | Before expiry | HTTP/SQL call | Denied; not early complete | Not tested | Not tested | DB-005 |
| PAY-T001 | Payments | Low | Webhook replay | Applied event | Replay body; old timestamp | Duplicate safe; old rejected | Not tested | Not tested | MKT-008 |
| PAY-T002 | Payments | High | Client cannot set amount | Pending order | Extra amount in checkout body | DB total charged | Not tested | Not tested | Verified control |

---

## 14. Recommended Fix Plan

| Priority | Finding ID | Component | Issue | Recommended Action | Dependencies |
|---|---|---|---|---|---|
| 1 | MKT-001 | Marketplace / Buyer | Void before capture; paid ignored | Block void with live session; refund on paid-after-void | `apply_paymongo_event`, refund API, buyer failure UI |
| 1 | MKT-002 | Marketplace | Auction paid webhook ignored | Accept in-window or refund | Second-chance offers, PayMongo refunds |
| 2 | AUTH-001 | Auth | JWT before OTP | Session after OTP/trusted device server-side | GoTrue, RLS, trusted devices |
| 2 | AUTH-002 | Auth | Bypass Edge lockout | Auth-wide lockout/captcha or disable password grant | Hosted Auth config |
| 2 | AUTH-004 | Auth | Fail open on RPC | 503 when throttle RPC fails | Same release as AUTH-002 |
| 2 | MKT-003 | Marketplace | Reconcile amount retry | Remove retry; alert on mismatch | `reconcile-paymongo-checkout` |
| 2 | SEL-001 | Seller / DB | PIN hash readable | Revoke column SELECT | Shipment embeds in UI |
| 2 | SA-001 | Superadmin / DB | Admin DELETE policy | Revoke DELETE; super_admin RPC | Live grant check |
| 2 | ADM-001 | Admin | Unlimited SMS test | Remove or cap function | UniSMS env |
| 2 | SEL-002 | Seller / DB | Listing validation client-only | DB CHECK on price, name, desc, stock | Checkout |
| 3 | DB-001, DB-005, ERR-001 | Backend | Open job RPC/HTTP | Revoke execute; cron secrets; generic errors | Schedulers |
| 3 | DB-002 | Backend | Escrow RPC open | Revoke authenticated execute | Triggers/service role |
| 3 | DB-003 | Admin / DB | Forged audit logs | Server-only log writes | Admin RPCs |
| 3 | MKT-006, MKT-005 | Marketplace | Stock + double session | Atomic restore; single PayMongo session | Webhook ordering |
| 3 | MKT-004 | Marketplace | Partial group paid | All siblings check | Multi-shop checkout |
| 3 | AUTH-003, AUTH-005, AUTH-006 | Auth / Admin | Session/oracle/deactivated admin | Global revoke; uniform errors | GoTrue |
| 3 | AUTH-007 | Auth | Weak email OTP | Match phone OTP limits | Mail quotas |
| 3 | BUY-VAL-*, SEL-VAL-*, ADM-VAL-* | Apps | Form/DB mismatch | Align limits after DB constraints | Product max lengths |
| 3 | SA-002 | Superadmin | Bootstrap email in migration | Remove from source | Ops procedure |
| 4 | AUTH-008, AUTH-009, AUTH-010 | Auth | Debug OTP, passwords, signup copy | Flags, Auth policy, generic UX | Product policy |
| 4 | MKT-007, MKT-008, MKT-009 | Marketplace | Preview, webhook time, listing cap | UI totals; timestamp window; cap on restore | Product decisions |
| 4 | DB-004, DB-008 | DB | Public bids, role in view | Policy/view changes | Product |

---

## 15. Items Requiring Further Verification

| Area | Related IDs | What to verify |
|---|---|---|
| Hosted Supabase | SA-001, DB-001, DB-002, DB-005 | RLS, GRANTs, function bodies match migrations |
| Hosted Auth | AUTH-002, AUTH-009, BUY-VAL-010 | Password grant, JWT TTL, captcha, password min |
| PayMongo | MKT-001, MKT-002, MKT-003 | Webhook URL/secret; refund path for ignore branches |
| Storage | SEL-VAL-005, ADM-VAL-003 | `product-images` bucket; avatar; latest policies on LF/reviews/reports |
| Network / device | ERR-008, ERR-009, XSYS-012 | Offline, double submit, Realtime, label vs status |
| Abuse / network | AUTH-013, RATE-008, XSYS-008 | IP header trust; banned token until expiry; session revoke on disable |
| Data quality | XSYS-009, SEL-VAL-009 | `NOT VALID` phone constraint; saved rider limits |
| Deployment | ADM-001, DB-001, DB-005 | Edge functions deployed in production |
| Tooling | — | Supabase security advisors on live project (not run in this audit) |

No application code was changed for this documentation restructure.

---

## Appendix: Legacy F-ID mapping (for prior readers)

| Legacy | New primary ID |
|---|---|
| F-01 | MKT-001 |
| F-02 | MKT-002 |
| F-03 | MKT-003 |
| F-04 | AUTH-001 |
| F-05 | AUTH-002 |
| F-06 | SEL-001 |
| F-07 | ADM-001 |
| F-08 | SA-001 |
| F-09 | AUTH-003 |
| F-10 | AUTH-004 |
| F-11 | AUTH-005 |
| F-12 | AUTH-006 |
| F-13 | DB-001 |
| F-14 | DB-002 |
| F-15 | DB-003 |
| F-16 | MKT-004 |
| F-17 | MKT-005 |
| F-18 | MKT-006 |
| F-19 | AUTH-007 |
| F-20 | SEL-002 |
| F-22 | SA-002 |
| F-23 | AUTH-008 |
| F-24 | AUTH-009 |
| F-25 | MKT-007 |
| F-26 | DB-004 |
| F-27 | MKT-008 |
| F-28 | MKT-009 |
| F-29 | AUTH-010 |
| F-30 | ERR-001 |
