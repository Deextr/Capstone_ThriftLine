# Phase 6 — Mandatory PayMongo payment (QR Ph)

**Status:** Revision in repo (2026-09-12). Apply the new SQL **after** the original Phase 6 files, redeploy Edge Functions, then device-test.  
**Update (2026-10-16):** New checkouts use **QR Ph only**. Card and GCash were removed from checkout. See [QR Ph, refunds, and payouts](#qr-ph-refunds-and-phase-a-payouts-2026-10-16) below.  
**Goal:** A ThriftLine purchase completes only after a **verified PayMongo webhook**. Failed, expired, or cancelled payment must not consume stock and must leave the item in the buyer cart.

---

## Lifecycle

```text
Cart → Checkout → QR Ph (PayMongo) → hosted checkout shows a QR code
        ↓
SUCCESS webhook                         FAIL / EXPIRE / CANCEL
        ↓                               ↓
payment paid                            void unpaid checkout once
order paid                              stock reservation released
cart line removed                       cart restored
seller: Paid / To ship                  no seller sale
```

There is **no Pay Later** product flow. `pending` is only a short technical state while PayMongo is open.

---

## What already existed (kept)

- Phase 5 `checkout_cart` still creates a `pending` order and calls `consume_product_stock` (row-locked). That deduction is now a **reservation**, not a completed sale.
- `create-paymongo-checkout` + `paymongo-webhook` + `apply_paymongo_event` stay the only paid path.
- Flutter never writes `orders` or `payments` to paid.
- Secrets stay in Edge Function env, not Flutter `.env`.

---

## New database file

Do **not** rewrite applied migrations. Apply:

| File | What it does |
| --- | --- |
| `20260912020000_mandatory_payment.sql` | `payments.paymongo_channel` (`card` / `gcash`), `restore_product_stock`, `void_unpaid_checkout`, `abandon_unpaid_checkout`, `expire_unpaid_checkouts`, `prepare_paymongo_checkout(order_id, channel)`, fail/expire voids, one-seller checkout, no unpaid “order placed” notifies |

Then run:

1. `supabase/introspection/phase6_verify.sql` (prepare signature is now `(uuid, text)`)
2. `supabase/introspection/phase6_mandatory_payment_verify.sql` (16 checks)

### Reservation / void (idempotent)

`void_unpaid_checkout` only runs when `order_status = pending`. It atomically:

1. Sets the order to `cancelled` (this is the once-only gate)
2. Marks the pending payment `failed`
3. Restores each `order_items` quantity via `restore_product_stock`
4. Upserts cart lines with `GREATEST` (does not add stock or cart qty twice)
5. Notifies the **buyer** only

A second fail webhook, or `abandon_unpaid_checkout` after a webhook void, hits the cancelled row and does nothing.

A success webhook after void or expiry still **records the PayMongo capture** when the provider confirms payment: the order stays cancelled (or the auction stays non-fulfillable), `payments` becomes `paid`, and escrow opens a **manual GCash refund** (`late_payment_after_cancellation` or `late_payment_after_auction_deadline`). Admins are notified via the existing buyer-refund workflow. No stock is consumed twice and the order is not reactivated.

### Expiry without Flutter

`expire_unpaid_checkouts()` voids **fixed-price** pending orders older than **90 minutes**. `prepare_paymongo_checkout` calls it. PayMongo `checkout_session.expired` / payment failed events also void immediately.

### Auction limitation (out of scope)

`ensure_auction_order` still consumes the unique auction unit on win. This revision **does not** auto-void auction orders (a unique `auction_id` would block a replacement order). Unpaid auction wins keep the reservation until a later auction-payment policy is defined. Auction pay still uses the same PayMongo screen from Bids → View order.

---

## Edge Functions

Redeploy after SQL:

```text
supabase functions deploy create-paymongo-checkout
supabase functions deploy reconcile-paymongo-checkout
supabase functions deploy paymongo-webhook --no-verify-jwt
supabase functions deploy paymongo-return --no-verify-jwt
```

`create-paymongo-checkout` accepts only `payment_method` = `qrph` and defaults to it (Flutter cannot send the amount). PayMongo `payment_method_types` is `['qrph']`. Buyers scan the QR code with GCash, Maya, or a bank app. Gateway is always PayMongo — there is no direct GCash API.

PayMongo `success_url` / `cancel_url` stay HTTPS (`paymongo-return`) because PayMongo requires a fully qualified https URL. Shared `*.supabase.co` functions rewrite GET `text/html` to `text/plain`, so that function returns a 302/`intent://` redirect instead of a bounce HTML page. Flutter then reconciles the real PayMongo status. The return URL never marks the order paid.

### PayMongo Dashboard (test mode)

1. Enable **QR Ph** under payment methods. If it is not listed, ask PayMongo support to activate it for the account.
2. Webhook URL: `https://<project-ref>.supabase.co/functions/v1/paymongo-webhook`
3. Subscribe at least to:
   - `checkout_session.payment.paid`
   - `payment.paid`
   - `payment.failed`
   - `checkout_session.payment.failed` (if listed)
   - `checkout_session.expired` (if listed)
   - `payment.refunded`
   - `payment.refund.updated`
4. Signing secret → `PAYMONGO_WEBHOOK_SECRET` (not the secret key).

Use the real PayMongo test page (**Authorize Test Payment** / **Fail / Expire Test Payment**). Do not fake those buttons in Flutter.

---

## Flutter

- Checkout → Pay with QR Ph. No method picker, no autostart, no Pay Later, no skip.
- Success: confirmation + View Order after the **order row** becomes paid (Realtime / resume).
- Failure / Return to Cart: `abandon_unpaid_checkout` + cart refresh → Checkout.
- Purchase History hides unpaid and failed checkouts.
- Seller Orders / dashboard hide unpaid reservations. Badge = **To ship** after paid.

---

## What Phase 6 is not

- Seller payout, wallets, escrow release
- Full refund / dispute workflow
- Auction payment timeout / re-list
- Direct GCash or Maya merchant APIs
- Live PayMongo keys (keep `sk_test_` / `whsk_test_` for development)

---

## QR Ph, refunds, and Phase A payouts (2026-10-16)

SQL and deploy steps are in `supabase/migrations/README.md` under
"QR Ph checkout, buyer refunds, and Phase A seller payouts".

### Buyer refunds

A refund decision (admin dispute refund, or the 72-hour fulfillment SLA)
cancels the order right away. The money is tracked separately in
`escrow.refund_state`:

| State | Meaning | Buyer sees |
| --- | --- | --- |
| `provider_pending` | PayMongo accepted the refund and has not finished it | Refund in progress |
| `awaiting_buyer_claim` | PayMongo returned a QR Ph claim link (expires in about 3 days) | Open PayMongo claim link |
| `manual_required` | PayMongo refused it, or there is no PayMongo payment id | Add GCash details |
| `succeeded` | PayMongo confirmed the refund | Refunded |
| `manual_completed` | An admin recorded a GCash transfer with a receipt | Refunded, with the GCash reference |

Rules the code enforces:

- ThriftLine always asks PayMongo for existing refunds on the payment before
  creating one, and adopts any refund that has not failed.
- If PayMongo gives no clear answer (timeout, 5xx, 429, auth errors), nothing
  is recorded as refused. The first attempt aborts. A retry keeps a lock that
  blocks the manual GCash path until an admin runs **Check PayMongo status**.
- While the last PayMongo attempt is unconfirmed, the database also blocks
  releasing that payment to the seller (`trg_escrow_guard_unconfirmed_refund`).
- `payments.payment_status` becomes `refunded` only for `succeeded` or
  `manual_completed`.
- A manual refund needs the exact refund amount, a GCash reference, the date
  sent, and a receipt in the private `financial-evidence` bucket.

QR Ph refunds use `https://refunds-api.paymongo.com/v1/refunds`. Refunds need
enough PayMongo balance; "insufficient balance" is a refusal that moves the
refund to `manual_required`.

### Seller payouts (Phase A, manual)

1. The seller requests a payout to their saved GCash. Only one open request
   is allowed, and the seller can cancel it.
2. An admin opens **Seller payouts** in the admin sidebar, sends the money from
   the ThriftLine GCash account outside the app, then records the amount,
   GCash reference, date, and receipt.
3. Only then is the payout `paid`. Rejected or cancelled requests return the
   amount to the seller's available balance.

ThriftLine does not send seller money. PayMongo Wallet, automated GCash
disbursements, InstaPay, and bank transfers are Phase B and not built.
