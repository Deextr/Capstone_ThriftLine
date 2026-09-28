# Phase 10 escrow — manual test checklist

Use three accounts: **Buyer**, **Seller**, and **Admin**. Pay with PayMongo test mode (GCash or card). Write down each `order_number` after checkout.

Escrow is an internal ledger. Flutter does not decide whether money is held, released, or refunded. Seller payout requests are recorded only. They do not send GCash.

## Before you start

Apply these in the Supabase SQL Editor if they are not already applied, in this order:

1. `supabase/migrations/20260914010000_phase10_settlement.sql`
2. `supabase/introspection/phase10_verify.sql` — expect **22 PASS** rows
3. `supabase/migrations/20260924010000_return_shipments.sql`
4. `supabase/migrations/20260924140000_fix_seller_earnings_snapshot.sql`

Deploy the refund function (same `PAYMONGO_SECRET_KEY` as checkout). Do not put that key in Flutter.

```text
npx supabase functions deploy resolve-delivery-payment
```

Also confirm Phase 6 checkout (`create-paymongo-checkout`, `paymongo-webhook`, `paymongo-return`) and Phase 7 delivery are already working.

The Admin account must be a real app user with `users.role = admin`.

## What each status means

| After this happens | `payments.payment_status` | `escrow.status` | Seller dashboard |
| --- | --- | --- | --- |
| Buyer pays | `paid` | `held` | Held earnings |
| Buyer opens a delivery problem | `paid` | `disputed` | Held earnings |
| Order completes, no open dispute | `paid` | `released` | Available earnings |
| Admin releases to the seller | `paid` | `released` | Available earnings |
| Admin refund succeeds | `paid` | `refunded` | Refunded. Not available. |
| Checkout cancelled, failed, or expired | not `paid` | no held row | Not a sale |

Available earnings = released seller amount minus recorded payout requests.

## Queries

Paste in **Supabase → SQL Editor**. Replace the order number.

**Find the latest orders**

```sql
SELECT order_id, order_number, order_status, created_at
FROM public.orders
ORDER BY created_at DESC
LIMIT 10;
```

**Payment and escrow**

```sql
SELECT
  o.order_number,
  o.order_status,
  p.payment_status,
  e.status AS escrow_status,
  e.seller_amount_centavos,
  e.released_at,
  e.refunded_at,
  e.release_reason,
  e.refund_provider,
  e.paymongo_refund_id
FROM public.orders o
JOIN public.payments p ON p.order_id = o.order_id
LEFT JOIN public.escrow e ON e.order_id = o.order_id
WHERE o.order_number = 'PASTE_ORDER_NUMBER';
```

**Delivery problem**

```sql
SELECT o.order_number, d.status AS dispute_status, d.created_at, d.resolved_at
FROM public.orders o
LEFT JOIN public.delivery_disputes d ON d.order_id = o.order_id
WHERE o.order_number = 'PASTE_ORDER_NUMBER'
ORDER BY d.created_at DESC NULLS LAST;
```

**Return after a refund**

```sql
SELECT
  o.order_number,
  e.status AS escrow_status,
  r.return_required,
  r.seller_pays_return,
  r.status AS return_status,
  r.rider_name
FROM public.orders o
LEFT JOIN public.escrow e ON e.order_id = o.order_id
LEFT JOIN public.return_shipments r ON r.order_id = o.order_id
WHERE o.order_number = 'PASTE_ORDER_NUMBER';
```

**Seller totals**

```sql
SELECT
  o.order_number,
  e.status AS escrow_status,
  e.seller_amount_centavos
FROM public.users u
JOIN public.escrow e ON e.seller_id = u.user_id
JOIN public.orders o ON o.order_id = e.order_id
WHERE u.email = 'PASTE_SELLER_EMAIL'
ORDER BY e.held_at DESC;
```

## Skip the 24-hour inspection (test only)

Normal completion waits until `inspection_expires_at`. To finish one delivered order immediately, run this only on a test order whose Delivery PIN is already verified:

```sql
DO $$
DECLARE
  v_order_number text := 'PASTE_ORDER_NUMBER';
  v_order_id uuid;
BEGIN
  SELECT o.order_id INTO v_order_id
  FROM public.orders o
  WHERE o.order_number = v_order_number;

  IF v_order_id IS NULL THEN
    RAISE EXCEPTION 'Order % not found', v_order_number;
  END IF;

  UPDATE public.shipments s
  SET inspection_expires_at = now()
  WHERE s.order_id = v_order_id
    AND s.delivery_status = 'inspection_period'
    AND s.delivery_verified_at IS NOT NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % is not in inspection', v_order_number;
  END IF;

  PERFORM public.complete_expired_inspections();
END
$$;
```

Then refresh the app. This does not release money if a delivery problem is still open.

---

## Test 1 — Pay creates a hold

1. Seller posts a cheap fixed-price listing.
2. Buyer adds it and checks out.
3. Buyer pays until PayMongo succeeds.

**Buyer:** Order leaves payment and can be tracked.

**Seller:** Dashboard **Held earnings** includes this sale. It is not on the Available Earnings card yet.

**SQL:** `payment_status = paid`, `escrow_status = held`, `order_status` is not `completed`.

**Pass:** One escrow row, status `held`.

**Fail:** Paid order with no escrow row, or the amount already shows as Available.

## Test 2 — Complete the order, then auto-release

1. Seller arranges delivery and the rider uses the Delivery PIN.
2. Buyer does not report a problem.
3. Either wait for inspection to end, or run the skip-inspection SQL above.
4. Buyer opens Track Order, or Seller opens the order, so `complete_expired_inspections` runs.

**Seller:** Order is completed. The amount moves to **Available earnings**. Status line is **Ready for payout**. Seller gets an “Earnings available” notification.

**SQL:** `order_status = completed`, `escrow_status = released`, `released_at` is set, `release_reason` is `order_completed`.

**Pass:** Released only after completion, with no open dispute.

**Fail:** Released while still shipping, or still `held` after a completed order with no dispute.

## Test 3 — Request payout (record only)

1. On the Seller Dashboard, use **Request payout** on the Available Earnings card.
2. Confirm the dialog.

**Seller:** Available earnings drop by the requested amount. A **Payout pending** line appears.

**SQL:**

```sql
SELECT amount_centavos, status, requested_at
FROM public.seller_payouts
WHERE seller_id = (SELECT user_id FROM public.users WHERE email = 'PASTE_SELLER_EMAIL')
ORDER BY requested_at DESC;
```

**Pass:** A `requested` payout row exists. Escrow stays `released`. No GCash transfer happens.

**Fail:** The app claims cash was sent, or Available goes below zero.

## Test 4 — Leave payment unpaid

1. Buyer starts checkout so an order is created.
2. On the payment screen, choose **Return to Cart** (or cancel in PayMongo).

**Buyer:** The item is back in the cart. It is not stuck as a hidden unpaid order.

**Seller:** The sale is not in Pending Payment.

**SQL:** Order is `cancelled` or the payment is not `paid`. There is no `held` escrow row.

**Pass:** Buyer and seller both show that this checkout did not become a sale.

**Fail:** Seller still shows Pending Payment after the buyer cancelled, or stock stays deducted.

If the buyer presses Back or closes the app **without** cancelling, the unpaid order should stay visible under Buyer **To Pay** / Checkout **Payment needed**, and the seller may still show Pending Payment. That is the same order. Continue payment must not create a second order.

## Test 5 — Delivery problem keeps the money held

1. Complete Test 1 and deliver with the PIN so inspection has started.
2. Buyer reports a **delivery problem** with photos before inspection ends.
3. Do not use a community report for this test.

**Seller:** Amount stays in **Held earnings**.

**Admin:** The case is in the delivery review list. Do not decide yet.

**SQL:** `dispute_status = open`, `escrow_status = disputed`.

**Pass:** Money does not auto-release while the dispute is open.

**Fail:** Escrow becomes `released` before Admin decides.

## Test 6 — Admin releases to the seller

1. Use the open case from Test 5.
2. Admin reviews the evidence and chooses **Release to Seller**.

**Seller:** Amount becomes **Available earnings**.

**Buyer:** No refund.

**SQL:** Dispute `resolved`, `escrow_status = released`, `paymongo_refund_id` is empty.

**Pass:** Seller receives it. Buyer is not refunded.

**Fail:** Escrow stays `disputed`, or a refund id appears.

## Test 7 — Admin refunds, no return

1. Start a new paid and delivered order.
2. Buyer opens a delivery problem.
3. Admin chooses **Refund Buyer**, then **No return needed**.

**Buyer:** Refund is done. No return rider is required.

**Seller:** Amount is **Refunded**. It is not on Available earnings.

**SQL:** `escrow_status = refunded`, `paymongo_refund_id` is filled for a PayMongo payment, `return_status = not_required`.

**Pass:** The refund does not wait for the seller to do anything.

**Fail:** The app says refunded but PayMongo has no refund, or the refund waits for a return.

## Test 8 — Admin refunds, return required

1. Repeat Test 7, but Admin chooses **Return required**.

**Buyer:** Still refunded immediately. Track Order shows the return only after a rider is assigned.

**Seller:** Order asks them to **Arrange return**. Enter rider name, phone, and vehicle.

**Buyer:** Confirm handoff when the rider takes the item.

**Seller:** Confirm the item is back.

**SQL after the refund:** `escrow_status = refunded` and `return_status = waiting_for_rider`, `seller_pays_return = true`.

Then: `rider_assigned` → `picked_up` → `returned`.

If Admin cancels the return, `return_status = cancelled_by_admin` and escrow stays `refunded`.

**Pass:** Refund and return are separate. The seller arranges the return.

**Fail:** The buyer must pay for the return, or the refund is reversed because the seller ignores it.

## Test 9 — Community report does not move money

1. On a completed, released order, file a community report (not a delivery problem).
2. Admin upholds or rejects it.

**SQL:** That order’s `escrow_status` stays `released`. No `return_shipments` row is created by the report.

**Pass:** The report is moderation only.

**Fail:** The report refunds the buyer or removes seller earnings.

---

## Short path if time is limited

1. Test 1 — hold
2. Test 2 — auto-release
3. Test 3 — payout record
4. Test 5 and Test 6 — dispute, then release
5. Test 7 — refund, no return
6. Test 8 — refund plus return

Mark each test **Pass** or **Fail** from the buyer screen, the seller Available/Held card, and the SQL row together. One of those three disagreeing means the test failed.
