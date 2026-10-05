# Initial Testing for ThriftLine

**Purpose:** Step-by-step manual QA for ThriftLine as **Buyer**, **Seller**, and **Admin**.  
**How to use:** Follow tests in order within each role. For each test, run the steps, compare with **Expected Result**, then mark **Pass** or **Fail** and add **Notes**.

**Before you start**

- Use a **test build** connected to the project Supabase/PayMongo test environment (not production money unless your team says otherwise).
- Prepare **three accounts** when possible: Buyer, Seller (approved), Admin.
- Some flows need **two buyers** (auction outbid) or **Buyer + Admin** (reports).
- Delivery addresses in the app are **Davao City only** (barangay picker).
- Buyer **Payment Methods** in Profile currently shows **“Coming soon”** (not a full feature yet). Seller **Payment Methods** is for **payout method** (GCash/Maya, etc.).

---

# Buyer Testing

Flow overview: **Splash → Login/Sign up → Verify email (if asked) → Home → Browse/Search → Product → Cart or Buy Now → Checkout → Complete payment (PayMongo) → My Purchases → Track Order → Confirm receipt → To Rate / Reviews → Reports & Profile**

---

## Splash & first open

### App opens to splash

**Steps:**
1. Install/open the ThriftLine app (cold start).

**Expected Result:** Splash screen appears briefly, then you are sent to **Login** (if logged out) or your home workspace (Buyer, Seller, or Admin if already signed in).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Authentication

### Create account (email sign up)

**Steps:**
1. On **Login**, go to **Sign up** (or equivalent link).
2. Enter **Full name**, **Email**, **Password**, and **Confirm password** (follow on-screen rules).
3. Accept terms/consent if shown.
4. Tap **Sign up**.

**Expected Result:** Account is created. You either see a message to check email, are taken to **Verify email** (6-digit code), or land on **Buyer Home** if verification is not required in your environment.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Sign up — passwords do not match

**Steps:**
1. On **Sign up**, enter different values in **Password** and **Confirm password**.
2. Try to submit.

**Expected Result:** Form shows an error; account is not created.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Login with email and password

**Steps:**
1. On **Login**, open **Sign in with email** (or email sign-in panel).
2. Complete **human verification** (Turnstile) if shown.
3. Enter valid email and password.
4. Sign in.

**Expected Result:** You reach **Buyer Home** (bottom tabs: Home, Bids, Looking, Messages, Profile).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Login — wrong password

**Steps:**
1. Use a registered email with an incorrect password.
2. Try to sign in.

**Expected Result:** Login fails with a clear error. You stay on Login. After repeated failures, a lockout message may appear.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Google Sign-In

**Steps:**
1. On **Login**, tap **Continue with Google** (Google sign-in button).
2. Complete Google account picker and consent.

**Expected Result:** You are signed in and land on the correct home (Buyer unless the account is Admin-only).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Verify email (6-digit OTP)

**Steps:**
1. After sign up (or when the app requires it), open **Verify email** screen.
2. Check email for a **6-digit code**.
3. Enter the code and verify.
4. Optional: tap resend and use a new code.

**Expected Result:** Valid code completes verification and opens **Buyer Home**. Invalid or short code shows an error. Resend sends a new code message.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Verify email — invalid OTP

**Steps:**
1. On **Verify email**, enter a wrong or incomplete code (e.g. 12345).

**Expected Result:** Error asking for the full 6-digit code; you are not logged in as a verified user.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Forgot password

**Steps:**
1. On **Login**, open **Forgot password**.
2. Enter your registered email.
3. Complete human verification if shown.
4. Submit.
5. Open the reset link from email (may open **Reset password** in app or browser, depending on setup).
6. Set a new password and sign in with it.

**Expected Result:** Reset email is sent (success state on screen). New password works on **Login**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Forgot password — unregistered email

**Steps:**
1. On **Forgot password**, enter an email that is not registered (if your team allows testing this).

**Expected Result:** App handles it safely (success-style message or clear error per product policy—no crash).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Logout (Buyer)

**Steps:**
1. Open **Profile** tab → scroll to **Logout**.
2. Confirm if asked.

**Expected Result:** Session ends; you return to **Login**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Buyer Home & discovery

### Buyer Home — browse sections

**Steps:**
1. Sign in as Buyer → **Home** tab.
2. Pull to refresh.
3. Tap search bar, cart bag icon, and notifications bell if shown.
4. Scroll home sections (e.g. banners, suggested items, ending soon, verified sellers—what your build shows).
5. Tap a product card.

**Expected Result:** Home loads products. Search opens **Search**. Bag opens **Cart**. Notifications open **Notifications**. Tapping a product opens **Product** details.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Search products

**Steps:**
1. From Home, open **Search**.
2. Type a keyword (e.g. a brand or “vintage”) and submit.
3. Tap a result.

**Expected Result:** Matching listings appear. Recent searches may be saved. Opening a result shows **Product** details.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Search filters

**Steps:**
1. On **Search**, open the **Filters** control.
2. Apply filters (category, price, condition, etc.—as available).
3. Apply and review results.
4. Reset filters.

**Expected Result:** Results update to match filters. Active filter chips show on Search. Reset clears filters.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Product details, favorites, shop

### Fixed-price product details

**Steps:**
1. Open a **fixed-price** listing (not auction).
2. Review photos, price, description, seller info.
3. Tap seller name/shop if available.

**Expected Result:** Details match the listing. Seller profile/shop opens where implemented.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Add to Cart (fixed price)

**Steps:**
1. On a fixed-price product with stock, tap **Add to Cart**.
2. Open **Cart** from Home bag icon or navigation.

**Expected Result:** Item appears in **Cart** with correct price and quantity controls.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Buy Now (skip cart)

**Steps:**
1. On a fixed-price product, tap **Buy Now**.
2. Continue through the buy-now/checkout path.

**Expected Result:** You reach checkout for that single item without needing Cart first.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Saved Items (favorites)

**Steps:**
1. On a product, save/favorite the item (heart or save control if shown).
2. **Profile** → **Saved Items**.

**Expected Result:** Saved product appears in **Saved Items**. Removing save removes it from the list.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Following Shops

**Steps:**
1. Follow a verified seller shop (from product or shop page if available).
2. **Profile** → **Following Shops**.

**Expected Result:** Shop appears in the list. Unfollow removes it.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Out of stock / cannot add to cart

**Steps:**
1. Open a product with **no stock** or unavailable state (ask dev team for a test listing).

**Expected Result:** **Add to Cart** / **Buy Now** is disabled or shows a clear message; checkout cannot start for that item.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Cart & Checkout

### Cart — select items and checkout

**Steps:**
1. Add one or more fixed-price items to **Cart**.
2. Select items to checkout (checkboxes if shown).
3. Tap **Checkout (n)**.

**Expected Result:** **Checkout** opens with selected items, subtotal, shipping, **Platform fee (2%)**, and total.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Empty cart

**Steps:**
1. Remove all items or open **Cart** with nothing in it.

**Expected Result:** Empty state message; checkout button disabled or not offered.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Checkout — delivery address

**Steps:**
1. On **Checkout**, set or confirm **delivery address** (Davao City barangay).
2. If no address exists, go to **Addresses** from Profile, add one, return to checkout.

**Expected Result:** Valid Davao address is required before payment. Invalid or incomplete address blocks continuing.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Checkout — continue to payment

**Steps:**
1. On **Checkout** with valid address, tap **Continue to payment (amount)**.
2. Wait for order creation.

**Expected Result:** **Complete payment** screen opens for the order(s). Multiple shops may become **separate orders** with one combined PayMongo payment.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Checkout blocked — unpaid auction win

**Steps:**
1. As a buyer who already has an unpaid **auction win** in **To Pay**, try to start a new fixed-price checkout from Cart.

**Expected Result:** Checkout is blocked with a message to pay the auction win first.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## PayMongo payment

### Complete payment — GCash or Card

**Steps:**
1. On **Complete payment**, choose **GCash** or **Card** (available channels).
2. Tap **Pay [amount]** (opens PayMongo).
3. Complete payment in PayMongo test flow.
4. Return to the app.

**Expected Result:** App shows **Confirming your payment...** then **Payment Successful** or redirects to **Order confirmation**. Order moves out of unpaid state.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Payment — cancel or abandon

**Steps:**
1. Start PayMongo checkout.
2. Cancel or close without paying.
3. Return to app.

**Expected Result:** Order stays pending or returns items to cart per fixed-price rules. Clear message to retry or return to cart. Seller sees order under **Pending** payment only while window is open.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Payment failed

**Steps:**
1. Use PayMongo test credentials/method that **fails** payment (team-provided).

**Expected Result:** **Payment Failed** (or similar). Buyer can retry or leave; order does not show as paid in **My Purchases**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Payment expired

**Steps:**
1. Create a pending checkout and let the payment window expire (or use test hook if available).

**Expected Result:** **Payment Expired** screen. Unpaid fixed-price checkout does not stay as a completed purchase; auction unpaid win moves to **Cancelled** in **My Purchases** when deadline passes.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## My Purchases & order lifecycle

### My Purchases — tabs

**Steps:**
1. **Profile** → **My Purchases**.
2. Switch tabs: **All**, **To Pay**, **Payment Confirmed**, **To Receive**, **Completed**, **Return/Refund**, **Cancelled**.

**Expected Result:** Orders appear under the correct tab for their status. Counts on chips match visible orders.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### My Purchases — no orders yet

**Steps:**
1. Use a new buyer account with no purchases → **My Purchases**.

**Expected Result:** Friendly empty message per tab (e.g. “Nothing to pay”).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Track Order

**Steps:**
1. Open a paid order → **Track Order** (from My Purchases or tracking entry).
2. Pull to refresh.

**Expected Result:** **Delivery Progress** timeline updates. Before shipping, message that tracking appears when seller ships. Rider/courier info shows when seller arranges delivery.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Delivery PIN

**Steps:**
1. On **Track Order**, when PIN is available, view **Delivery PIN**.
2. Do not share PIN until you physically have the parcel (per on-screen warning).

**Expected Result:** PIN displays for buyer to give rider at handoff when applicable.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Inspect order — I received my order

**Steps:**
1. When order is in **inspection** phase on **Track Order**, read the inspection timer.
2. Tap **I received my order**.

**Expected Result:** Confirmation message. Button disables after confirm. Inspection window can continue until it ends.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Report a problem (delivery / order)

**Steps:**
1. During inspection on **Track Order**, tap **Report a problem**.
2. Choose a reason, add details (minimum length if enforced), add evidence photos if optional.
3. Submit.

**Expected Result:** Report submits successfully. Order may show under **Return/Refund** or disputed state. Buyer can see related status on tracking.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Completed order — leave review

**Steps:**
1. After order is **Completed**, open **Track Order** or **Profile** → **To Rate**.
2. Leave star rating and review text for the seller.
3. Submit.

**Expected Result:** Review saves. **To Rate** count decreases. Review appears under **To Rate** → reviews tab if implemented.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Purchase history (auction wins awaiting payment)

**Steps:**
1. If you have an auction win, check **Purchase history** entry from Profile if available.

**Expected Result:** Unpaid auction wins show with deadline reminder to pay before time runs out.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Auctions & Bids

### View live auction on product

**Steps:**
1. Open an **auction** listing.
2. Note current bid, time left, and bid history if shown.

**Expected Result:** Auction details are visible. **Place Bid** available while auction is active.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Place bid — success

**Steps:**
1. On an active auction, tap **Place Bid**.
2. Enter a valid bid above minimum/next bid.
3. Confirm bid (**Confirm Bid**).

**Expected Result:** Bid is accepted. You are leading bidder or see updated highest bid. Bid appears under **Bids** tab.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Place bid — invalid (too low)

**Steps:**
1. Enter a bid below the required minimum.

**Expected Result:** Error; bid is not placed.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Outbid by another buyer

**Steps:**
1. **Buyer A** places a bid.
2. **Buyer B** places a higher bid before auction ends.

**Expected Result:** **Buyer A** sees they are outbid in **Bids** tab / product page. **Buyer B** leads.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Auction ends — winner To Pay

**Steps:**
1. Wait for auction to end (or use test listing with short duration).
2. Winning buyer opens **My Purchases** → **To Pay**.

**Expected Result:** Winner sees obligation to pay with deadline text (“You won this auction…”). **Pay** flow opens **Complete payment**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Auction winner — pay before deadline

**Steps:**
1. Winner completes PayMongo payment before **payment due** time.

**Expected Result:** Order moves to **Payment Confirmed** / normal fulfillment. Seller sees paid order in **To Ship**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Auction winner — does not pay before deadline

**Steps:**
1. Let payment deadline pass without paying (test environment).

**Expected Result:** Order appears under **Cancelled** in winner’s **My Purchases**. Seller listing may become inactive; seller may **Offer to next bidder** or **Relist** if rules allow (multiple bids).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Looking For (buyer)

### Browse Looking For requests

**Steps:**
1. **Looking** tab → browse feed.
2. Change sort: **Recently Posted**, **Most Popular**, **Highest Budget**.

**Expected Result:** Posts load and sort changes.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Create Looking For post

**Steps:**
1. Tap create (+) on **Looking** tab.
2. Fill title, description, budget, category, etc.
3. Post.

**Expected Result:** “Request posted.” Post appears in **My requests** section of Looking tab.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Looking For — share with sellers

**Steps:**
1. Open your post → **Share** (if available).
2. Select sellers and send.

**Expected Result:** “Request shared with selected sellers.”

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Report a Looking For post

**Steps:**
1. On another user’s post, open report option.
2. Submit report.

**Expected Result:** Report submits; admin can review under **Looking For Reports** (see Admin section).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Messages (Chat)

### Chat list and send message

**Steps:**
1. **Messages** tab.
2. Open a conversation (or start from product/seller if available).
3. Send a text message.

**Expected Result:** Message sends and appears in thread. Seller/buyer receives it when using second device/account.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Trust & Safety (Buyer)

### Report a Seller (community)

**Steps:**
1. **Profile** → **Trust & Safety** → **Report a Seller**.
2. Pick a reason (e.g. Scam or Fraud, Harassment).
3. Add details and evidence if required.
4. Submit.

**Expected Result:** Success message. Report appears in **My Reports** as **Under Review**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### My Reports — view status

**Steps:**
1. **Profile** → **My Reports**.
2. Open a report detail.

**Expected Result:** Shows reason, date, status (**Under Review**, **Resolved**, **Action Taken**, or **Dismissed**) and admin response when closed.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Report — duplicate / too fast (negative)

**Steps:**
1. Submit the same report twice in a short time (if applicable).

**Expected Result:** App blocks duplicate or rate-limited submit with clear message (no crash).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Account review (appeal)

**Steps:**
1. If your test account has an account restriction, open **Account review** from the link or route your team provides.

**Expected Result:** **Account review** screen loads appeal details and lets user respond if implemented.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Profile, addresses, settings

### Edit Profile

**Steps:**
1. **Profile** → **Edit Profile**.
2. Change display name or photo (if allowed).
3. Save.

**Expected Result:** Profile updates across app header.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Addresses (buyer delivery)

**Steps:**
1. **Profile** → **Addresses**.
2. Add/edit/delete a Davao address.
3. Set default if option exists.

**Expected Result:** Addresses save and appear at checkout.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Phone number verification

**Steps:**
1. Open **Phone number** screen (from profile/edit flow if linked).
2. Enter PH mobile number, request code, enter OTP, verify.

**Expected Result:** “Phone number verified.” Invalid number or OTP shows error.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Notifications toggle (Profile)

**Steps:**
1. **Profile** → toggle **Notifications** for buyer.

**Expected Result:** Toggle saves (or shows error if save fails).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Notifications screen

**Steps:**
1. Home bell → **Notifications**.
2. Open a notification if any exist.

**Expected Result:** List loads; tapping navigates to relevant screen when deep link exists.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Settings & legal docs

**Steps:**
1. **Profile** → **Settings**.
2. Toggle push/email notifications.
3. Open **Help & FAQ**, **Terms and Conditions**, **Privacy Policy**, **About ThriftLine**.

**Expected Result:** Preferences save. Legal pages open and scroll.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Payment Methods (buyer) — coming soon

**Steps:**
1. **Profile** → **Payment Methods**.

**Expected Result:** Snackbar or message **Coming soon** (no full payment wallet setup for buyers).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

# Seller Testing

Flow overview: **Buyer account → Become a Seller → Wait for Admin → Switch to Seller → Dashboard / Listings / Orders → Arrange delivery → Completed → Analytics & My Shop**

**Needs Admin account** for approval steps.

---

## Become a Seller (from Buyer)

### Start seller application

**Steps:**
1. Buyer **Profile** → **Become a Seller**.
2. **Step 1 of 4 — Seller information & address:** store name, address lines, Davao barangay.
3. Tap **Continue**.

**Expected Result:** Moves to ID step. Invalid or incomplete fields block continue.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### ID verification (Step 2)

**Steps:**
1. Choose ID type.
2. Capture **front** (and **back** if required) using in-app camera.
3. Continue when quality checks pass.

**Expected Result:** ID images accepted or clear retake prompts.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Face verification (Step 3)

**Steps:**
1. **Take a selfie** / liveness step.
2. Tap **Continue to selfie** / complete capture.

**Expected Result:** Selfie marked uploaded; proceed to step 4.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Past selling experience (Step 4 — optional)

**Steps:**
1. Optionally add claimed selling range and external transaction proofs.
2. Submit application.

**Expected Result:** Application submits. Screen shows **Verification Status** / **Application Under Review** with timeline (Submitted → Document Review → Shop Activation).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Pending application — cannot re-apply

**Steps:**
1. While status is **pending**, open **Become a Seller** again.

**Expected Result:** Pending status screen only; no duplicate submission.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Rejected application

**Steps:**
1. Use a test account rejected by Admin (see Admin tests).
2. Open **Become a Seller**.

**Expected Result:** Rejection reason shown; option to fix and re-apply if implemented.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Switch to Seller Mode

### Switch Account (Buyer ↔ Seller)

**Steps:**
1. After Admin **approves** seller, on Buyer **Profile**, use avatar **Switch Account** or **Switch Account** menu.
2. Choose **Seller** workspace.

**Expected Result:** Bottom tabs change to **Dashboard**, **Listings**, **Looking**, **Orders**, **Messages**, **Profile** (seller).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Seller Dashboard & shop

### Seller Dashboard

**Steps:**
1. **Dashboard** tab.
2. Review earnings/summary cards and shortcuts.

**Expected Result:** Dashboard loads without error; pending order badge on **Orders** if applicable.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### My Shop & Trust Score

**Steps:**
1. **Profile** → **My Shop**.
2. View shop info and **Trust Score** panel.

**Expected Result:** Shop name and trust score/breakdown display. Pull to refresh updates data.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Shop address

**Steps:**
1. **Profile** → **Shop address**.
2. Update seller pickup/shop address (Davao).

**Expected Result:** Address saves and reflects on listings/orders as designed.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Analytics Report

**Steps:**
1. **Profile** → **Analytics Report**.
2. Change date period if filters exist.

**Expected Result:** Earnings and **Completed orders** stats show for selected period.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Payment Methods (seller payout)

**Steps:**
1. **Profile** → **Payment Methods**.
2. Set or update **Payout method** (e.g. GCash/Maya details per form).

**Expected Result:** Payout details save for seller payouts.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Listings

### Create fixed-price listing

**Steps:**
1. Open **Add listing** (from Listings tab or dashboard shortcut).
2. Choose **Fixed Price**.
3. Add title, description, category, condition, photos, price, stock.
4. Publish listing.
5. **Listings** tab → **Active**.

**Expected Result:** Listing publishes and appears in **Active**. Buyers can see it in search/home.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Create auction listing

**Steps:**
1. **Add listing** → **Auction**.
2. Set start price, **Auction Duration**, photos, details (quantity is 1).
3. Publish.
4. Confirm in **Active** tab while auction runs.

**Expected Result:** Auction goes live with countdown. Bids tab on buyer side can bid.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### View listing (seller preview)

**Steps:**
1. From **Listings**, open a listing (owner preview).

**Expected Result:** Product page opens in preview mode for seller.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Edit listing (active only)

**Steps:**
1. Edit an **Active** fixed-price or live auction listing.
2. Save changes.

**Expected Result:** Changes save. Ended/sold listings cannot be edited (controls hidden or disabled).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Listing tabs — Awaiting Payment / Sold / Inactive

**Steps:**
1. After auction ends with unpaid winner, check **Awaiting Payment** bucket.
2. After paid sale, check **Sold**.
3. After cancelled/expired auction, check **Inactive**.

**Expected Result:** Listings appear in correct seller listing tabs.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### End auction early (if bids exist)

**Steps:**
1. On active auction with at least one bid, use **End early** if shown.

**Expected Result:** Auction ends; winner flow starts.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Offer to next bidder

**Steps:**
1. After winner fails to pay (deadline passed) and there were **2+ bids**, use **Offer to next bidder** / **Offer to 2nd Highest Bidder**.

**Expected Result:** Next bidder gets To Pay obligation; listing updates accordingly.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Relist auction

**Steps:**
1. On inactive unpaid auction, tap **Relist** / **Relist Auction**.
2. Confirm duration and relist.

**Expected Result:** New auction goes active.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Seller orders

### Pending payment (buyer paying)

**Steps:**
1. Buyer starts checkout but has not paid.
2. Seller **Orders** → **Pending**.

**Expected Result:** Order appears with **Pending Payment**; message about PayMongo checkout.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### To Ship — paid order

**Steps:**
1. After buyer pays, open **Orders** → **To Ship**.
2. Open order detail.

**Expected Result:** Payment confirmed message. **Arrange Delivery** available when ready.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Arrange Delivery — local rider

**Steps:**
1. On order detail, tap **Arrange Delivery**.
2. Choose **Freelance / Local Rider** (seller arranged).
3. Pick from **Saved Riders** or enter rider details.
4. Save/submit.

**Expected Result:** Shipment updates. Buyer sees rider contact on **Track Order** when policy allows.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### My Riders — saved riders

**Steps:**
1. **Profile** → **My Riders**.
2. Add a rider via editor screen.
3. Edit or remove a rider.

**Expected Result:** Riders list updates and appear in **Arrange Delivery** picker.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Order status actions (seller)

**Steps:**
1. For local rider flow, use actions such as **Mark Ready for Pickup**, **Mark Picked Up**, **Mark Out for Delivery** as they appear on order detail.

**Expected Result:** Buyer timeline advances. Order moves to **Shipped** bucket when out for delivery.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Delivery problem (seller)

**Steps:**
1. If seller can record a delivery problem (sheet on order), submit reason.

**Expected Result:** Order shows delivery issue state; buyer may see warning on tracking.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Completed orders (seller)

**Steps:**
1. After buyer completes inspection/PIN flow, check **Orders** → **Completed**.

**Expected Result:** Order listed as completed with date.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Cancelled orders (seller)

**Steps:**
1. View unpaid expired or cancelled sales under **Cancelled**.

**Expected Result:** Cancelled sales listed; not mixed with active fulfillment.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Arrange Return (if return flow open)

**Steps:**
1. When buyer return/dispute is active, open **Arrange Return** from order if available.
2. Follow return arrangement steps.

**Expected Result:** Return status updates for buyer **Return/Refund** tab.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Seller — Looking For & Messages

### Browse Looking For as seller

**Steps:**
1. Seller **Looking** tab (browse only, no create FAB).
2. Tap **I Have This** on a buyer request.

**Expected Result:** Message or chat flow starts / confirmation per app behavior.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Seller Messages

**Steps:**
1. **Messages** tab as seller.
2. Reply to buyer.

**Expected Result:** Same chat behavior as buyer side.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Seller settings & logout

### Seller Settings & notifications

**Steps:**
1. **Profile** → **Settings**.
2. Toggle seller push/email notifications.

**Expected Result:** Saves for seller workspace.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Logout (Seller)

**Steps:**
1. **Profile** → **Logout**.

**Expected Result:** Returns to Login.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

# Admin Testing

Flow overview: **Admin Login → Dashboard → Verifications → Reports (Community / Order / Looking For) → Settings → Logout**

Admin uses bottom/rail tabs: **Dashboard**, **Verifications**, **Reports**, **Settings**.

---

## Admin login

### Admin sign in

**Steps:**
1. Log in with an **admin** account (email or Google, per team setup).

**Expected Result:** Lands on **Admin** workspace (**Dashboard** tab), not Buyer/Seller shell.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Dashboard

### Dashboard overview & date filters

**Steps:**
1. Open **Dashboard**.
2. Try filters: **Today**, **Last 7 days**, **Last month**, **Last year**, **Custom** (date range picker).
3. Tap **Refresh**.

**Expected Result:** **Registered users** and **Active users** counts update for the period. **Pending verifications** and **Open reports** cards show counts.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Dashboard shortcuts

**Steps:**
1. Tap **Pending verifications** card.
2. Go back to Dashboard; tap **Open reports** card.

**Expected Result:** Opens **Verifications** tab and **Reports** tab respectively.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Pending verifications list (dashboard section)

**Steps:**
1. On Dashboard, scroll to pending seller applications snippet.
2. Open an application.

**Expected Result:** Navigates to seller review detail.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Seller Verifications

### Verifications queue — Pending

**Steps:**
1. **Verifications** tab (**Seller Verifications**).
2. Open **Pending** (or pending filter).
3. Select an application.

**Expected Result:** Applicant store info, ID images, selfie, and optional past selling history visible.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Approve seller application

**Steps:**
1. On review screen, tap **Approve seller**.
2. Confirm **Approve this seller?**

**Expected Result:** Application leaves Pending; status **Approved**. User can **Switch Account** to Seller on buyer profile.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Reject seller application

**Steps:**
1. On another test application, tap **Reject application**.
2. Choose rejection reason in dialog and confirm.

**Expected Result:** Application rejected; buyer sees rejection on **Become a Seller**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Reports

### Reports hub — categories

**Steps:**
1. **Reports** tab.
2. Review hub cards: **Community Reports**, **Order Reports**, **Looking For Reports**, **All Reports** (wording as shown).

**Expected Result:** Each category opens its queue list.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Reports queue filters

**Steps:**
1. Inside a category queue, filter by **Under Review**, **Resolved**, **Closed**, or **All** (as available).
2. Sort **Newest** / **Oldest** if available.

**Expected Result:** List matches filter. Open reports show **Under Review** status chip.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Report details — decide open report

**Steps:**
1. Open an **Under Review** report.
2. Choose one decision: **Record action taken**, **Resolve report**, or **Dismiss report**.
3. Enter **Response to reporter** (minimum length enforced—at least 8 characters).
4. Save/submit decision.

**Expected Result:** Report closes with chosen status. Reporter sees updated status and admin response in **My Reports**.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Report details — already closed

**Steps:**
1. Open a closed report.

**Expected Result:** Decision and admin response shown read-only; no decision form.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Disabled accounts

**Steps:**
1. On **Reports** hub, tap **Disabled accounts** icon (person-off icon in app bar).
2. Review list.

**Expected Result:** **Disabled accounts** screen loads restricted users (if any).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Looking For report detail (admin)

**Steps:**
1. From **Looking For Reports** queue, open a report.
2. Take moderation action (e.g. **Dismissed** / confirm violation—labels as on screen).

**Expected Result:** Looking For post/report status updates per admin action.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Delivery Problems (admin)

> **Note:** The app includes **Delivery Problems** screens for order delivery disputes. There may be **no menu button** on the admin tab bar in the current build. Ask your dev team how to open **Delivery Problems** for testing (e.g. internal link) after a buyer submits **Report a problem** on **Track Order**.

### Delivery Problems queue (when accessible)

**Steps:**
1. Open **Delivery Problems**.
2. Toggle **Open** / **Closed** filter.
3. Open a dispute.

**Expected Result:** Shows buyer, seller, order, reason, and details. Admin can close/resolve when allowed.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Admin settings & logout

### Admin Settings

**Steps:**
1. **Settings** tab (admin shell).
2. Change notification preferences; open legal/support links.

**Expected Result:** Same **Settings** content as other roles where applicable. **Logout** available on this tab for admin.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

### Admin logout

**Steps:**
1. **Settings** → **Logout**.

**Expected Result:** Returns to Login.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

# Connected Tests (Multi-role)

Use separate devices or accounts. Mark each party’s result.

---

## Seller listing → Buyer purchase

| Role | Action |
|------|--------|
| **Seller** | Publish fixed-price listing in **Active**. |
| **Buyer** | Find product via Search/Home → **Add to Cart** → pay. |

**Expected Result:** Buyer sees paid order in **My Purchases**. Seller sees order in **To Ship** (not Pending).

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Buyer pays → Seller fulfills → Buyer receives

| Role | Action |
|------|--------|
| **Seller** | **Arrange Delivery** → mark out for delivery. |
| **Buyer** | **Track Order** → see timeline and rider/PIN if applicable → **I received my order**. |

**Expected Result:** Seller order moves toward **Completed** after inspection rules complete.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Buyer review → Seller My Shop

| Role | Action |
|------|--------|
| **Buyer** | Leave review from **To Rate** or completed **Track Order**. |
| **Seller** | Open **My Shop** / public seller profile as buyer. |

**Expected Result:** New review visible on seller shop/reviews section.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Buyer report → Admin decision → Buyer My Reports

| Role | Action |
|------|--------|
| **Buyer** | Submit **Report a Seller** → **Under Review** in **My Reports**. |
| **Admin** | Open same report in **Community Reports** → **Resolve** or **Dismiss** with response. |
| **Buyer** | Refresh **My Reports** / report detail. |

**Expected Result:** Status changes from **Under Review** to admin’s decision; response text visible to buyer.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Auction multi-buyer

| Role | Action |
|------|--------|
| **Seller** | Publish short auction. |
| **Buyer A** | Bid. |
| **Buyer B** | Higher bid before end. |
| **Buyer B** | Pay after win. |

**Expected Result:** A is outbid; B has **To Pay** then paid order; A does not win.

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

# End-to-End Testing

---

## Fixed-Price Order (full happy path)

| Step | Who | Action | Expected Result |
|------|-----|--------|-----------------|
| 1 | Seller | Create **Fixed Price** listing, publish | In **Listings → Active**; visible to buyers |
| 2 | Buyer | Search/open product | Product details correct |
| 3 | Buyer | **Add to Cart** → **Checkout (n)** | Checkout totals include shipping + 2% platform fee |
| 4 | Buyer | **Continue to payment** → PayMongo **GCash** or **Card** | **Payment Successful** / order confirmation |
| 5 | Buyer | **My Purchases → Payment Confirmed** | Order listed |
| 6 | Seller | **Orders → To Ship** | Paid order visible |
| 7 | Seller | **Arrange Delivery**, progress shipment statuses | Buyer tracking updates |
| 8 | Buyer | **Track Order**, delivery PIN if shown | Timeline and rider info correct |
| 9 | Buyer | **I received my order** during inspection | Confirmation saved |
| 10 | System | Wait for inspection window to complete | **Completed** for both sides |
| 11 | Buyer | **To Rate** → submit review | Review saved |
| 12 | Seller | **Orders → Completed**, **Analytics** | Sale completed; stats include order |

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Auction Order (full happy path)

| Step | Who | Action | Expected Result |
|------|-----|--------|-----------------|
| 1 | Seller | Create **Auction**, publish | Live countdown |
| 2 | Buyer A | **Place Bid** | Bid recorded |
| 3 | Buyer B | Higher **Place Bid** | A outbid |
| 4 | System | Auction ends | B is winner |
| 5 | Buyer B | **My Purchases → To Pay** | Deadline shown |
| 6 | Buyer B | Pay via PayMongo before deadline | Moves to fulfillment |
| 7 | Seller | Process like fixed-price (ship/delivery) | Same shipment flow |
| 8 | Buyer B | Confirm receipt | **Completed** |
| 9 | Buyer B | Review seller | Review posted |

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

## Auction — winner does not pay

| Step | Who | Action | Expected Result |
|------|-----|--------|-----------------|
| 1 | Seller | Auction with **2+ bidders**, ends with winner | Winner To Pay created |
| 2 | Winner | Do **not** pay before deadline | — |
| 3 | Winner | Check **My Purchases → Cancelled** | Unpaid win cancelled |
| 4 | Seller | **Listings** inactive/awaiting; try **Offer to next bidder** if enabled | Second bidder may get To Pay **or** **Relist** available |

- [ ] Pass  
- [ ] Fail  

**Notes:**

---

# Bug Report Template

Copy this block for each issue found.

---

## Bug Title

**Role:** Buyer / Seller / Admin  

**Feature/Screen:**  

**Steps to Reproduce:**
1.  
2.  
3.  

**Expected Result:**  

**Actual Result:**  

**Error Message:**  

**Screenshot/Video:**  

**Pass/Fail:**  

**Notes:**  

---

*Document generated from the ThriftLine app codebase (routes and screens as implemented). Update this guide when new features ship.*
