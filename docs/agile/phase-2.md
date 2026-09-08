# Phase 2 — Catalog and Discovery

**Status:** Code complete — apply `20260908010000_phase2_catalog.sql`, then test  
**Goal:** Real buyer home, search, product detail, saved items, seller public profile, and My Shop, backed by Supabase. Bidding, chat, cart checkout, and payments stay later phases.

---

## What Phase 2 Is

From the ThriftLine backend blueprint:

> Products revision (search vector, indexes, `quantity_available`), `saved_items`, `follows`, `looking_for_posts` fix. Makes functional: buyer home, search, product detail, saved items, seller public profile, My Shop.

This is **not** auctions (Phase 3), chat (Phase 4), or cart/orders (Phase 5). Coworker files that already exist for those later phases were left in place and were not rewritten.

---

## Database

Apply after Phase 1, in filename order:

| File | What it does |
| --- | --- |
| `20260908010000_phase2_catalog.sql` | Renames `products.title` → `name` when needed; adds `quantity_available`, `sold_at`, `search_vector`; catalog indexes; `increment_product_view()`; favorite-count trigger; `follows` + RLS; looking-for `description` / `category_id` / `location` |
| `20260909010000_looking_for_reference_images.sql` | Optional Looking For reference image column + public `looking-for` bucket; lets authenticated users read comments on open requests |
| `20260909020000_conversations.sql` | Direct-message tables used by Looking For share / I Have This. Full chat (realtime, receipts) stays Phase 4. |

Then run `supabase/introspection/phase2_verify.sql`. Every row should say `PASS`. Apply `20260909010000` and `20260909020000` in the SQL Editor as well — reference photos, sharing to followed sellers, and I Have This fail until those files run.

Already applied earlier (keep them, do not duplicate):

- `20260902010000_saved_items_rls.sql` — owner-only saved items
- Listing INSERT already gated by Phase 0 `is_approved_seller()`

Out of Phase 2 scope (coworker extras — do not treat as Phase 2 complete):

- `20260907020000_cart_items.sql`
- `20260907030000_bidding_system.sql`
- `20260907040000_ensure_auctions.sql`

---

## Flutter

- Buyer home, search, product detail, and saved items read `products` + `product_images` + `categories` without embedding `user_public_profiles` (PostgREST cannot join that view). Seller names come from `seller_profiles` / `user_public_profiles` in a second query, scoped to the seller ids on the page.
- Search uses sanitized `ilike` on name/brand/description so it still works if `search_vector` is missing; the GIN index is for later ranking.
- Product cards and the profile saved-count use `SavedItemsProvider`, not mock `DataProvider`.
- Product views increment through `increment_product_view`, not a client `UPDATE`.
- Follow on a public seller profile writes `follows`. Follower counts are read from the `follows` table (not the denormalized `seller_profiles.follower_count` alone). Self-follow is blocked. Edit Public Profile on your own shop is Seller-workspace only.
- Looking For posts insert/select `looking_for_posts`. Buyers create, edit, and delete their own requests (RLS is owner-only for write/delete). Buyers can share a request to sellers they follow; the share is a chat message that links the original `post_id`. Sellers use I Have This to message the request owner. The Looking For tab shows a spinner until the first fetch finishes.
- My Shop lists the signed-in seller's real products.

---

## How To Test

1. Apply the Phase 2 SQL as an approved seller.
2. Add a listing (fixed price). Confirm it appears on buyer home after refresh.
3. Search by name/brand. Open the product. Confirm the view count can rise (reload detail).
4. Heart the product. Confirm Saved Items and the profile saved count match.
5. Open the seller public profile. Follow, then unfollow.
6. Post a Looking For request. Confirm it remains after restart.
7. Switch to the Seller account → My Shop. Confirm the new listing is there.

Phone OTP, Become a Seller, and admin review must still work (Phase 1). Do not expect checkout or live bidding to be finished here.

---

## Security

- Product create/update still requires `is_approved_seller()` (Phase 0).
- Saved items and follows are owner-scoped.
- Looking-for insert is `auth.uid() = user_id` and `status = open`.
- View counts are RPC-only.
- Public catalog still cannot read other users' email/phone (`user_public_profiles`).
