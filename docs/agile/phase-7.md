# Phase 7 — Freelance rider delivery monitoring

**Status:** Implementation complete in repo (2026-09-12). Apply the SQL, deploy the Edge Function, then device-test seller arrange-delivery and buyer Track Order.  
**Goal:** After PayMongo marks an order **paid**, the seller arranges a freelance / local rider, the buyer verifies handover with a Delivery PIN, and the transaction completes after a 24-hour inspection period unless a delivery problem is reported.

There is **no** courier integration, rider account, GPS tracking, escrow, or seller payout in this phase.

---

## Lifecycle

```text
PayMongo paid → shipment seller_preparing
        ↓
Seller assigns freelance rider
        ↓
Ready for pickup → picked up → out for delivery (PIN generated once)
        ↓
Buyer shows PIN only after the parcel is in hand
        ↓
Seller submits PIN → backend verifies → inspection_period (24h)
        ↙                         ↘
No dispute / window ends          Report a problem
        ↓                              ↓
Both statuses completed            Both statuses disputed
```

`confirm_delivery` only records `buyer_confirmed_received`. It does **not** complete the order and does **not** release payout.

---

## Database

Do **not** rewrite Phase 5/6 payment files. Apply:

| File | What it does |
| --- | --- |
| `20260912030000_phase7_delivery.sql` | `shipments`, PIN secrets, delivery events/disputes, paid-order trigger, delivery RPCs, Realtime on `shipments` |

Then run `supabase/introspection/phase7_verify.sql`. Every row should say `PASS` (20 checks).

Do **not** create a `couriers` table. Do **not** use the legacy courier `shipping` table or write `orders.courier` / `orders.tracking_number`.

Inspection length is `inspection_period_hours()` = **24**. Flutter reads `inspection_expires_at` only.

To prove auto-complete without waiting 24 hours:

```sql
UPDATE public.shipments
SET inspection_expires_at = now() - interval '1 minute'
WHERE order_id = '<paid-and-verified-order>';

SELECT public.complete_expired_inspections();
```

The order and shipment should become `completed` with `auto_completed = true`.

---

## RPCs

Clients never UPDATE `shipments` or `orders` for delivery. Use:

- `assign_freelance_rider` (seller)
- `advance_delivery` (`ready_for_pickup` / `picked_up` / `out_for_delivery`)
- `get_my_delivery_pin` (buyer only)
- `verify_delivery_pin` (seller)
- `confirm_delivery` (buyer)
- `report_delivery_problem` (buyer)
- `mark_delivery_failed` (seller, out for delivery only)
- `complete_expired_inspections` (lazy from the app + scheduled Edge Function)

Unpaid / failed / expired checkouts are rejected by the backend.

---

## Edge Function

Deploy `supabase/functions/complete-expired-inspections` and schedule it like `close-auctions` (about once a minute). The Flutter order screens also call the RPC on load so completion still happens if the schedule is late.

```text
supabase functions deploy complete-expired-inspections
```

---

## Flutter

- Seller order detail: Arrange Delivery, milestone buttons, PIN verify, failed-delivery reason
- Buyer Track Order: freelance-rider timeline, masked rider info, Delivery PIN, inspection countdown, confirm / report
- Seller tabs: To Ship = preparing; Shipped = in transit / inspection / failed / disputed; Completed = completed only

---

## Done-checks

1. Paid order appears in seller **Paid / To Ship** and can start Arrange Delivery.
2. Unpaid / failed / expired checkout is rejected by `assign_freelance_rider`.
3. Rider assignment creates one shipment; buyer sees masked rider details.
4. Buyer cannot assign a rider.
5. Mark picked up updates the timeline and notifies the buyer.
6. Out for delivery makes the PIN available to the buyer.
7. Seller cannot read `delivery_pin_secrets` or the PIN hash.
8. Wrong PIN fails and increments attempts.
9. Correct PIN moves delivery to inspection.
10. Submitting the same correct PIN again is `already_verified` (no duplicate verify).
11. Buyer confirm sets `buyer_confirmed_received`; seller cannot call `confirm_delivery`.
12. After inspection expires with no dispute, `complete_expired_inspections` completes the order without Flutter remaining open.
13. An open delivery dispute blocks auto-complete.
14. Duplicate assign / advance / confirm calls do not create a second shipment or a second active PIN.
15. Another buyer/seller cannot read or mutate the shipment (RLS + RPC checks).
