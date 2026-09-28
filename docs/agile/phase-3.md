# Phase 3 — Auctions and Bidding

**Status:** Implementation complete in repo (2026-09-09). Apply `20260909030000_phase3_auctions.sql`, run `phase3_verify.sql`, deploy `close-auctions`, then device-test.  
**Goal:** Real `auctions` / `bids` records, server-side `place_bid`, scheduled/lazy `close_auctions`, Supabase Realtime, Bids tab from `v_user_bids`. Not orders, not PayMongo, not live sessions.

---

## What Phase 3 Is

An auction listing is not a product with `listing_type = auction`. It is:

```text
product (listing_type = auction)
        ↓
auctions row (starting_price, minimum_increment, ends_at, status)
        ↓
bids via place_bid only
        ↓
close_auctions → winner_id from highest bid
```

Existing names are kept: `bid_amount`, `ends_at`, status `ended` (not `closed`).

---

## Database

Apply after Phase 2, in filename order. Do **not** rewrite the coworker files.

| File | What it does |
| --- | --- |
| `20260907030000_bidding_system.sql` | Coworker original (already in tree) |
| `20260907040000_ensure_auctions.sql` | Coworker original (already in tree) |
| `20260909030000_phase3_auctions.sql` | Corrective: unique `product_id`, drop hardcoded trigger, RPC-only writes, `close_auctions`, `v_user_bids`, outbid/won notifications |

Then run `supabase/introspection/phase3_verify.sql`. Every row should say `PASS`.

### RPCs

- `place_bid(p_auction_id, p_amount)` — authenticated buyers only. Locks the auction row, rejects seller/self, inactive, expired (`now()` vs `ends_at`), and amounts below `current_price + minimum_increment`. Inserts the bid, updates price/leader, notifies the previous leader (`outbid`).
- `ensure_product_auction(...)` — seller of that product. Creates or (if there are no bids yet) updates the auction with the listing form’s increment and duration. If the product insert succeeded and this RPC fails, Flutter deletes the product.
- `close_auctions()` — expires `active` rows with `ends_at <= now()`, sets `winner_id` from the highest bid, notifies winner (`wonBid`) and seller (`system`). Idempotent. Does **not** create orders.
- `settle_ended_auctions()` — wrapper that calls `close_auctions()` so the coworker name still works.

### Security

Clients have `SELECT` on `auctions` and `bids`. `INSERT`/`UPDATE`/`DELETE` privileges are revoked from `authenticated`. Writes go through SECURITY DEFINER RPCs. RLS `WITH CHECK (true)` policies exist only so those RPCs work: on hosted Supabase, `postgres` is not a superuser, so FORCE RLS would otherwise block DEFINER inserts (same pattern as `notifications_insert_definer`).

Direct `bids.insert` from the Flutter anon key must fail after this SQL is applied.

### Scheduling

There is no `pg_cron` in this repo. Deploy `supabase/functions/close-auctions` and schedule a POST about every minute. Opening product detail or the Bids tab also runs `close_auctions`.

---

## Flutter

- Add Listing / Edit Listing call `ensure_product_auction` instead of inserting `auctions` rows.
- Product detail loads `auctions` + `bids`, subscribes to those tables for that `auction_id`, and places bids only through `place_bid`.
- Countdown uses server `ends_at`. It is UX only; the RPC enforces expiry.
- Bids tab reads `v_user_bids` (`winning` / `outbid` / `won` / `lost`) and hydrates products from the catalog query. No `DataProvider` fallback for this tab.

---

## How To Test

1. Paste `20260909030000_phase3_auctions.sql` into the SQL Editor. Run `phase3_verify.sql`.
2. Seller: create an auction listing (start price, increment, 1/3/5/7 days). Confirm an `auctions` row exists with those values — not a hardcoded ₱20 / 3 days.
3. Buyer A: open the product, confirm current price, min next bid, countdown. Place a bid at the minimum. Confirm success and bid history.
4. Buyer B: bid higher. Confirm A’s UI/Bids tab shows Outbid and A gets an `outbid` notification.
5. Seller account: confirm Place Bid is rejected.
6. Bid below minimum: rejected by RPC, not only by the text field.
7. After `ends_at`, run `SELECT public.close_auctions();` (or wait for the Edge Function / next screen open). Confirm status `ended`, winner, `wonBid` notification, Bids tab Won/Lost. A further `place_bid` is rejected.
8. Run `SELECT public.close_auctions();` again. Winner notifications must not duplicate.

Phone OTP, Become a Seller, catalog, and Looking For must still work. Do not expect checkout or PayMongo here.

---

## Remaining (device / dashboard)

- Apply the SQL in Studio (this environment cannot reach the hosted database).
- Deploy and schedule `close-auctions`.
- Confirm Realtime on a physical device (two buyers, no pull-to-refresh).
- Concurrent double-submit is covered by `FOR UPDATE` in `place_bid`; still worth tapping Place Bid twice quickly on a device.
