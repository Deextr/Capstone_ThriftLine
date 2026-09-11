# Phase 4 — Messaging

**Status:** Implementation complete in repo (2026-09-10). Apply `20260910010000_phase4_messaging.sql`, run `phase4_verify.sql`, then device-test Realtime and attachments.  
**Goal:** Live `conversations` / `messages` inbox with Supabase Realtime, last-read state, product-linked threads, and private image attachments. Not orders, not PayMongo, not livestream chat.

---

## What Phase 4 Is

Phase 2 already created `conversations` and `messages` for Looking For share and I Have This. Phase 4 keeps those tables and makes the existing Flutter chat feel like a real inbox:

```text
conversations (pair + optional product_id, last_read_at_a/b)
        ↓
messages (text / looking_for / offer / image)
        ↓
Realtime INSERT on messages, UPDATE on conversations
        ↓
ChatListController / ChatDetailController
```

Offers stay **messages only**. Checkout and payments are later phases.

---

## Database

Do **not** rewrite `20260909020000_conversations.sql`. Apply the new file after Phase 3:

| File | What it does |
| --- | --- |
| `20260909020000_conversations.sql` | Phase 2 tables + participant RLS (already applied) |
| `20260910010000_phase4_messaging.sql` | `product_id`, last-read columns, sender trigger, last_message trigger, `mark_conversation_read`, private `message-attachments`, Realtime publication |

Then run `supabase/introspection/phase4_verify.sql`. Every row should say `PASS`.

### Uniqueness

- One **general** thread per pair: unique `(participant_a, participant_b) WHERE product_id IS NULL`. Looking For and I Have This use this thread.
- One **listing** thread per pair + product: unique `(participant_a, participant_b, product_id) WHERE product_id IS NOT NULL`.

`participant_a < participant_b` is unchanged.

### Read state

`last_read_at_a` / `last_read_at_b` are the source of truth. `mark_conversation_read(uuid)` sets only the caller's column. Authenticated clients **cannot UPDATE** `conversations`; the message insert trigger owns `last_message` / `last_message_at` and advances the sender's last-read.

### Sender

A BEFORE INSERT trigger sets `messages.sender_id := auth.uid()`. Flutter omits `sender_id` from the insert payload.

### Storage

Private bucket `message-attachments`. Object path `{conversation_id}/{auth.uid()}/{uuid}.ext`. SELECT/INSERT require the caller to be a conversation participant. Use signed URLs, never public URLs.

### Realtime

`conversations` and `messages` are in `supabase_realtime`. RLS still applies, so User C does not receive events for a thread between A and B.

---

## Flutter

- `ConversationService` still owns open/create, send, Looking For share, and I Have This. It now takes optional `productId`, uploads private images, marks read via RPC, and does not client-update `conversations`.
- `ChatListController` / `ChatDetailController` subscribe to Realtime, dispose the channel, and dedupe messages by `message_id`.
- Buyer and seller Messages tabs embed the real inbox (`ChatInboxView`). The `/chat` route remains for dashboard shortcuts.
- Product Detail Chat opens or creates the **product-linked** thread, then pushes `/chat/:id`.
- Seller public profile Message opens the **general** thread with that shop.

---

## How To Test

1. Paste `20260910010000_phase4_messaging.sql` into the SQL Editor. Run `phase4_verify.sql`.
2. Buyer Messages tab: confirm real threads (not “Open Messages”).
3. Product Detail → Chat: confirm a thread titled with the seller and the listing name.
4. Same buyer/seller, second product → Chat: a **second** thread.
5. Send text on device A; device B sees it without leaving the thread.
6. Inbox preview, time, and unread dot update on B. Opening the thread clears unread. Restart the app: unread stays gone.
7. Looking For share and I Have This still land in the general pair thread and appear live.
8. Offer still inserts `message_type = offer` and does not create an order.
9. Image: pick a JPEG/PNG, confirm a private object under `{conversation_id}/{user_id}/`, recipient sees it via signed URL. A non-participant must not be able to download it.
10. SQL/API: inserting `sender_id` as another user still stores `auth.uid()`. Selecting another user's conversation returns zero rows.

Phone OTP, Become a Seller, catalog, auctions, and Looking For must still work. Do not expect checkout or PayMongo here.

---

## Security

- Conversation SELECT/INSERT: participant only.
- Message SELECT: participant. INSERT: participant, and `sender_id` is overwritten to `auth.uid()`.
- No client UPDATE/DELETE on `messages`. No client UPDATE grant on `conversations`.
- Attachments are not in a public bucket.
