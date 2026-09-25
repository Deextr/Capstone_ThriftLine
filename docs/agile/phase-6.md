# Phase 6 — Mandatory PayMongo payment (Card + GCash)

**Status:** Revision in repo (2026-09-12). Apply the new SQL **after** the original Phase 6 files, redeploy Edge Functions, then device-test.  
**Goal:** A ThriftLine purchase completes only after a **verified PayMongo webhook**. Failed, expired, or cancelled payment must not consume stock and must leave the item in the buyer cart.

---

## Lifecycle

```text
Cart → Checkout → Card or GCash (PayMongo) → hosted test checkout
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

A success webhook after void is **ignored** (order stays cancelled; payment is not marked paid).

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

`create-paymongo-checkout` now requires `payment_method` = `card` or `gcash` (Flutter cannot send the amount). PayMongo `payment_method_types` is that one channel. Gateway is always PayMongo — there is no direct GCash API.

PayMongo `success_url` / `cancel_url` stay HTTPS (`paymongo-return`) because PayMongo requires a fully qualified https URL. Shared `*.supabase.co` functions rewrite GET `text/html` to `text/plain`, so that function returns a 302/`intent://` redirect instead of a bounce HTML page. Flutter then reconciles the real PayMongo status. The return URL never marks the order paid.

### PayMongo Dashboard (test mode)

1. Enable **Card** and **GCash** under test payment methods.
2. Webhook URL: `https://<project-ref>.supabase.co/functions/v1/paymongo-webhook`
3. Subscribe at least to:
   - `checkout_session.payment.paid`
   - `payment.paid`
   - `payment.failed`
   - `checkout_session.payment.failed` (if listed)
   - `checkout_session.expired` (if listed)
4. Signing secret → `PAYMONGO_WEBHOOK_SECRET` (not the secret key).

Use the real PayMongo test page (**Authorize Test Payment** / **Fail / Expire Test Payment**). Do not fake those buttons in Flutter.

---

## Flutter

- Checkout → payment method (Cards / GCash). No autostart, no Pay Later, no skip.
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
