# Phase 5 — Cart → Checkout → Real Orders

**Status:** Implementation complete in repo (2026-09-11). Apply `20260911010000_phase5_orders.sql`, run `phase5_verify.sql`, then device-test checkout and seller Orders.  
**Goal:** Fixed-price cart/checkout and auction wins create real `orders` / `order_items` with **payment pending**. Not PayMongo, not GCash, not settlement.

---

## What Phase 5 Is

```text
Fixed-price listing → Add to cart / Buy Now → Checkout (saved address)
        ↓
checkout_cart RPC (server price, stock lock, one order per seller)
        ↓
orders + order_items → matching cart lines deleted in the same transaction
        ↓
Buyer confirmation / purchase history
        ↓
Seller Orders tab
```

Auction path:

```text
close_auctions → winner_id → ensure_auction_order (idempotent unique auction_id)
        ↓
Winner views pending order (Bids → View order)
        ↓
Payment stays pending (Phase 6)
```

---

## Database

Do **not** rewrite `20260907020000_cart_items.sql` or `20260909030000_phase3_auctions.sql`. Apply this new file after Phase 4:

| File | What it does |
| --- | --- |
| `20260907020000_cart_items.sql` | Existing cart + RLS (already applied) |
| `20260911010000_phase5_orders.sql` | Extends the **existing** `orders` / `order_items` tables (adds `order_number`, address snapshot, item title/qty, etc.), `checkout_cart`, `ensure_auction_order`, `set_order_address`, winner orders from `close_auctions` |

Then run `supabase/introspection/phase5_verify.sql`. Every row should say `PASS` (15 checks).

The hosted database already has `orders` and `order_items` from the original schema. Those tables use `order_status` / `order_type` / `total_amount` — there is **no** `order_number` until this migration adds it. Do not `DROP` the existing tables.

Existing `order_status_enum` values are `pending, paid, shipped, delivered, completed, cancelled, disputed`. Phase 5 inserts **`pending` only**. `paid` is reserved for Phase 6.

### Checkout RPC

`checkout_cart(p_address_id, p_product_id default null, p_quantity default null)`:

- Buyer is always `auth.uid()`.
- Address must belong to that buyer; a **snapshot** is stored on the order.
- Prices come from `products.price`, not Flutter.
- Fixed-price + `active` only. Auction listings cannot be bought this way.
- One order **per seller**. Shipping ₱80 per order. Platform fee 2% of that order’s subtotal.
- `FOR UPDATE` on product rows + `consume_product_stock` inside the transaction.
- Cart lines for purchased products are deleted **after** orders exist. Failure rolls back the cart delete.
- Buy Now still requires a cart line for that product (double-tap after success cannot invent a second purchase without a cart row).
- Advisory lock per buyer against double-submit races.

Clients **SELECT** orders. They cannot INSERT/UPDATE `orders` or `order_items`. Stock consume is postgres/service_role only.

### Auction orders

`ensure_auction_order(auction_id)` is called from `close_auctions` (including a backfill of already-ended auctions with a winner and no order). Unique index `orders_auction_id_uidx` prevents duplicates. Authenticated clients cannot execute `ensure_auction_order` directly.

If the winner has no address yet, `shipping_address` is `{}` and they attach one later with `set_order_address`.

Payment stays **`order_status = pending`**. Do not write `paid`. There is no PayMongo / GCash / webhook in this phase. The foundation `payments` table is left unread; clients cannot insert payment rows.

---

## Flutter

- Existing checkout UI is kept. **Place order** calls `checkout_cart`, then confirmation uses the returned `order_id`.
- Address card uses the Phase 1 address book (default, or Change → Addresses).
- `CartProvider.refresh()` runs **after** a successful RPC so the cart matches the database.
- Buyer confirmation, tracking, purchase history, seller Orders, seller dashboard recent orders, and the seller nav badge read Supabase through `BuyerOrdersController` / `SellerOrdersController`.
- Won auctions: Bids tab **View order** (not Buy Now / fake payment).
- Payment proof does **not** mark the order paid.

`DataProvider` mock orders remain in the tree for unrelated prototype screens. Production order flows do not use them.

---

## How To Test

1. Paste `20260911010000_phase5_orders.sql` into the SQL Editor. Run `phase5_verify.sql` (15 checks).
2. Buyer: add a **fixed-price** listing to cart → Checkout → saved address → Place order. Confirmation shows a real `TL-…` number. Cart line is gone. Seller Orders shows the same order as **Awaiting payment**.
3. Buy Now on product detail: only that product is purchased; other cart lines remain.
4. Checkout with no address: blocked with a clear message.
5. Two sellers in one cart: two orders, ₱80 shipping each.
6. Tap Place order twice quickly: one purchase, not two.
7. Change the listing price in Studio, then checkout: order uses the **database** price.
8. Last unit: two buyers should not both succeed.
9. Win an auction, wait for `close_auctions` (Bids tab also calls it). Winner sees **View order**. Run close again: still one order.
10. Seller cannot open another seller’s `/seller-order/:id`. Buyer cannot open someone else’s order.

Do **not** expect GCash/PayMongo. Payment pending is the correct end state.
