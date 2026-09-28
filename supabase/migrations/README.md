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

## One email → one account

| File | Purpose |
| --- | --- |
| `20260905020000_prevent_cross_provider_identity_link.sql` | Blocks attaching an **email/password** identity onto a Google/OAuth user |
| `20260907010000_allow_google_identity_on_email_user.sql` | Same function, corrected: Google sign-in onto an existing email user is allowed |

Apply `20260907010000` even if you already ran `20260905020000`. The older
function body rejected **any** second provider, so Google login onto an
email/password account (including the Studio admin user) returned
`Error creating identity`.

Apply this after the email OTP migration. It does **not** delete or merge
existing rows. If Google auto-link already attached a password to a Google
user, run `../introspection/duplicate_identities_report.sql` and clean those
up separately.

In the Dashboard, set **Authentication → Providers → (identity linking)** to
**Manual** if the control is available, so GoTrue itself refuses unauthenticated
linking. The trigger is the repo-owned enforcement.

## Seed data

`../seed/` holds environment-specific data that is deliberately not part of the
migration chain, because it depends on accounts that exist only in one project.

`001_role_assignments.sql` promotes `dexter041711@gmail.com` to admin. Create
that account in Studio first — GoTrue owns `auth.users` and hand-written rows
there break at login. Passwords are never stored in this file.

## Phase 2 — catalog and discovery

| File | Purpose |
| --- | --- |
| `20260908010000_phase2_catalog.sql` | Product `name` / search vector / quantity, `follows`, looking-for columns, view-count RPC |
| `20260909010000_looking_for_reference_images.sql` | Optional `reference_image_url`, public `looking-for` storage bucket, open-thread response SELECT |
| `20260909020000_conversations.sql` | Minimal `conversations` / `messages` for Looking For share and I Have This (Phase 4 can expand these) |

Run `../introspection/phase2_verify.sql` afterwards. Saved-items RLS was already added in `20260902010000_saved_items_rls.sql`. Cart and bidding migrations dated `20260907` are later-phase coworker work, not Phase 2. Apply `20260909010000` as well if buyers will attach reference photos or sellers will read comments on open requests.

## Phase 3 — auctions and bidding

Coworker files (keep in history, do not re-run as the source of truth):

| File | Purpose |
| --- | --- |
| `20260907030000_bidding_system.sql` | Original `place_bid`, `settle_ended_auctions`, client `bids_insert_own`, Realtime publication |
| `20260907040000_ensure_auctions.sql` | Trigger that auto-created auctions with a hardcoded ₱20 increment and 3-day duration |

Corrective file (apply this):

| File | Purpose |
| --- | --- |
| `20260909030000_phase3_auctions.sql` | RPC-only bids, `close_auctions()`, `ensure_product_auction()`, `v_user_bids`, RLS privilege revoke, unique `product_id` |

Run `../introspection/phase3_verify.sql` afterwards; every row should say `PASS`.

Deploy `../functions/close-auctions` and schedule it about once a minute (Dashboard → Edge Functions → Schedules, or pg_cron calling `SELECT public.close_auctions()`). The Flutter app also calls `close_auctions` when opening an auction or the Bids tab, so expiry still settles if the cron job is late. Phase 5 `20260911010000_phase5_orders.sql` extends `close_auctions` so a winner also gets an idempotent pending order.

## Phase 4 — messaging

| File | Purpose |
| --- | --- |
| `20260909020000_conversations.sql` | Phase 2 `conversations` / `messages` (already applied; do not rewrite) |
| `20260910010000_phase4_messaging.sql` | Product-linked threads, last-read columns, sender trigger, private `message-attachments`, Realtime publication |

Run `../introspection/phase4_verify.sql` afterwards; every row should say `PASS`. Looking For share and I Have This keep using `product_id IS NULL`. Offers remain chat messages (no orders).

## Phase 5 — cart, checkout, real orders

Do **not** rewrite `20260907020000_cart_items.sql`. Apply this after Phase 4:

| File | Purpose |
| --- | --- |
| `20260911010000_phase5_orders.sql` | Extends existing `orders` / `order_items` (adds `order_number`, snapshots), `checkout_cart`, `ensure_auction_order`, `set_order_address`, winner orders from `close_auctions` |
| `20260911020000_listing_stock.sql` | Auction stock clamped to 0–1, cart qty cannot exceed live stock, `add_to_cart` caps quantity, `checkout_cart` returns remaining-stock errors |

Run `../introspection/phase5_verify.sql` then `../introspection/phase5_stock_verify.sql`. Checkout and auction-win orders stay **payment pending**. PayMongo / GCash / webhooks are Phase 6.

Buyer delivery addresses are Davao City only. Apply `20260911030000_addresses_davao_city.sql` and run `../introspection/addresses_davao_verify.sql`.

## Phase 6 — PayMongo payment collection

Do **not** rewrite Phase 5 order/checkout migrations. Apply these after `20260911030000`:

| File | Purpose |
| --- | --- |
| `20260911040000_phase6_paymongo_enum.sql` | Adds `paymongo` to `payment_method_enum`. Run this file **by itself** and wait for success before the next file. |
| `20260911040100_phase6_paymongo.sql` | PayMongo columns, unique pending/paid payment indexes, webhook event log, checkout/webhook RPCs, Realtime on `orders` |

Run `../introspection/phase6_verify.sql` afterwards; all 16 checks should report `PASS`.

Edge Functions live in `../functions/create-paymongo-checkout`, `../functions/paymongo-webhook`, and `../functions/paymongo-return`. Deploy them and set **only** server-side secrets:

```text
PAYMONGO_SECRET_KEY=sk_test_...
PAYMONGO_WEBHOOK_SECRET=whsk_test_...
```

Never put those values in Flutter `.env`. Disable JWT verification on `paymongo-webhook` and `paymongo-return`. See `../../docs/agile/phase-6.md`.

## Phase 7 — freelance rider delivery

Do **not** rewrite Phase 6 payment files or create a `couriers` table. Apply after mandatory payment:

| File | Purpose |
| --- | --- |
| `20260912030000_phase7_delivery.sql` | `shipments`, PIN secrets, delivery events/disputes, paid-order trigger, delivery RPCs |

Run `../introspection/phase7_verify.sql` afterwards; all 20 checks should report `PASS`.

Deploy `../functions/complete-expired-inspections` and schedule it about once a minute, the same way as `close-auctions`. Opening Track Order or seller order detail also calls `complete_expired_inspections()`. See `../../docs/agile/phase-7.md`.

If checkout fails with `DELETE requires a WHERE clause` (code `21000`), apply `20260912010000_checkout_temp_delete.sql` and run `../introspection/checkout_temp_delete_verify.sql`. That is a hosted `pg-safeupdate` guard on `DELETE FROM tmp_checkout_lines`, not a PayMongo problem.

## Phase 8 — reviews and community reports

| File | Purpose |
| --- | --- |
| `20260913020000_phase8_reviews_reports.sql` | Reviews, `reports`, `report_evidence`, `submit_report`, `decide_report` later in Phase 9 |

Run `../introspection/phase8_verify.sql` afterwards.

## Phase 9 — Admin Review Center

| File | Purpose |
| --- | --- |
| `20260913030000_phase9_admin_review.sql` | Admin `decide_report` and `close_delivery_dispute` (no money movement) |

Run `../introspection/phase9_verify.sql` afterwards; all 16 checks should report `PASS`.

## Phase 10 — held payments, refund/release, seller earnings, payouts, appeals

Do **not** edit earlier migrations. `escrow` is an internal ledger, not a regulated third-party escrow product.

| File | Purpose |
| --- | --- |
| `20260914010000_phase10_settlement.sql` | `escrow`, `seller_payouts`, `report_appeals`, hold/release triggers, admin money RPCs, seller snapshot/payout, reported-user notice + appeal |

Run `../introspection/phase10_verify.sql` afterwards; all 22 checks should report `PASS`.

Deploy `../functions/resolve-delivery-payment` with the same `PAYMONGO_SECRET_KEY` used by checkout. Flutter must never receive that key. Seller payouts are **recorded requests only** — they do not send GCash.

## Item return after a delivery-problem refund

| File | Purpose |
| --- | --- |
| `20260924010000_return_shipments.sql` | `return_shipments` plus rider/handoff RPCs. Created only after the payment is already refunded. |

Redeploy `resolve-delivery-payment` after this SQL. The buyer refund does not wait for the seller to assign a rider. Community reports still do not move money or start a return.

## Unpaid checkout sync after leaving payment

| File | Purpose |
| --- | --- |
| `20260924130000_sync_my_unpaid_checkouts.sql` | Lets the signed-in buyer run `expire_unpaid_checkouts()` after leaving payment or reopening the app |

Apply this after the Phase 6 mandatory-payment file. It does not move money.

## Seller earnings snapshot query

| File | Purpose |
| --- | --- |
| `20260924140000_fix_seller_earnings_snapshot.sql` | Fixes `seller_earnings_snapshot` so activity and payout lists aggregate without treating `item` as a table |

Apply this after Phase 10. The dashboard card stays the same; only the RPC query changes.

## Auction payment window

| File | Purpose |
| --- | --- |
| `20260925120000_auction_payment_window.sql` | 12-hour winner payment, one second-bidder fallback, early end, relist, sold only after payment |

Apply after Phase 6 payment and Phase 5 orders. `close_auctions` still settles ended auctions and now also expires unpaid winner offers.

## Seller GCash payout method

| File | Purpose |
| --- | --- |
| `20260925130000_seller_gcash_payout_method.sql` | Saved GCash destination; `request_seller_payout` requires it |

Apply after Phase 10. Payouts stay recorded requests. `seller_payouts.status = requested` is unchanged.

## Selected cart checkout

| File | Purpose |
| --- | --- |
| `20260928120000_checkout_selected_cart.sql` | Checks out only the cart lines the buyer selected, using the same stock lock, order, and payment path as `checkout_cart` |

Apply after mandatory payment. Buy Now still calls `checkout_cart` for one product. Checking out more than one selected cart line requires this function.

## Orders per seller at checkout

| File | Purpose |
| --- | --- |
| `20260928130000_checkout_orders_per_seller.sql` | Selected checkout keeps every shop; one order, shipping total, and later escrow per seller |

Apply after `20260928120000_checkout_selected_cart.sql` if that file already ran. If it never finished, running only this file is enough because it replaces both functions. PayMongo stays one payment per order so escrow stays with the right seller.

## Conventions

- Authorization lives in RLS policies and `SECURITY DEFINER` helpers, never in
  the Flutter client.
- Helper functions used inside policies must be `SECURITY DEFINER` with an
  explicit `SET search_path`, otherwise a policy on `users` that calls a function
  reading `users` will recurse.
- Column-level write protection uses `BEFORE UPDATE` triggers, because Postgres
  RLS operates on rows, not columns.
