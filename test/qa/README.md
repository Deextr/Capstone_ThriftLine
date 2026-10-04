# ThriftLine QA Test Suite

Automated QA testing suite implementing structured **Unit Tests**, **Widget Tests**, and **Integration Tests** using `flutter_test` and `integration_test`.

---

## 1. Overview & Test Types

| Test Type | Scope | Framework | Location |
| :--- | :--- | :--- | :--- |
| **Unit Test** | Individual functions & classes | `flutter_test` | [test/qa/unit/](file:///c:/Users/user/projects/Capstone_ThriftLine/test/qa/unit) |
| **Widget Test** | Individual screens & reusable widgets | `flutter_test` | [test/qa/widget/](file:///c:/Users/user/projects/Capstone_ThriftLine/test/qa/widget) |
| **Integration Test** | End-to-end user journeys & critical flows | `integration_test` | [test/qa/integration_test/](file:///c:/Users/user/projects/Capstone_ThriftLine/test/qa/integration_test) |

---

## 2. Status Output Format

Each test automatically prints real-time status output:
* **Per Test**: `print('  ✅ <test_name> passed')` or `print('  ❌ <test_name> FAILED')`
* **Per Test Type**: Section summary and breakdown:
  ```text
  ══════════════════════════════════════════════════════════════
    ▶ UNIT TESTS  ·  Individual functions/classes  ·  flutter_test
  ══════════════════════════════════════════════════════════════
    ✅ Validators › email › accepts a valid address passed
    ...
  ──────────────────────────────────────────────────────────────
    UNIT TEST        ✅ PASSED (110/110)
  ```
  ```text
  ══════════════════════════════════════════════════════════════
    ▶ WIDGET TESTS  ·  Individual screens/widgets  ·  flutter_test
  ══════════════════════════════════════════════════════════════
    ✅ ThriftButton › renders its label and fires onPressed passed
    ...
  ──────────────────────────────────────────────────────────────
    WIDGET TEST      ✅ PASSED (41/41)
  ```
  ```text
  ══════════════════════════════════════════════════════════════
    ▶ INTEGRATION TESTS  ·  End-to-end integration flows  ·  integration_test
  ══════════════════════════════════════════════════════════════
    ✅ Authentication Integration Flow › full sign-up registration with validation & role assignment passed
    ✅ Buyer Checkout Integration Flow › full order checkout flow with Davao delivery, fees & placement passed
    ✅ Seller Listing Integration Flow › verified seller creates fixed-price product successfully passed
    ✅ Auction & Bidding Integration Flow › full bidding cycle with increments, validation & outbid handling passed
    ✅ Payment & Settlement Integration Flow › full PayMongo GCash payment flow with centavos conversion & state updates passed
    ✅ Chat & Messaging Integration Flow › buyer-to-seller conversation with text & offer messages passed
    ✅ Notification Inbox Integration Flow › buyer workspace filters seller notifications and manages read state passed
    ✅ Order Tracking & Delivery Integration Flow › full delivery lifecycle from preparing to buyer-confirmed completion passed
    ✅ Trust & Safety Integration Flow › buyer leaves review with star rating and comment validation passed
    ✅ Profile & Account Mode Integration Flow › profile edit validates name and saves normalized user data passed
    ...
  ──────────────────────────────────────────────────────────────
    INTEGRATION TEST ✅ PASSED (32/32)
  ```
* **Suite Summary**: Overall tallies printed upon completion:
  ```text
  ══════════════════════════════════════════════════════════════
    THRIFTLINE QA TEST STATUS
  ══════════════════════════════════════════════════════════════
    UNIT TEST        ✅ PASSED (110/110)
    WIDGET TEST      ✅ PASSED (41/41)
    INTEGRATION TEST ✅ PASSED (32/32)
    OVERALL          ✅ PASSED (183/183)
  ══════════════════════════════════════════════════════════════
  ```

---

## 3. Directory Structure

```text
test/qa/
├── qa_suite_test.dart            # Main QA test suite entry point (Unit + Widget + Integration)
├── README.md                     # QA suite documentation
├── support/
│   └── qa_reporter.dart          # Status tracking and real-time print reporter
├── unit/                         # Unit tests (functions & domain classes)
│   ├── ai_search_parser_unit.dart
│   ├── enums_unit.dart
│   ├── formatters_unit.dart
│   ├── helpers_unit.dart
│   ├── models_unit.dart
│   ├── money_and_stock_unit.dart
│   ├── ph_phone_unit.dart
│   ├── providers_unit.dart
│   ├── rider_privacy_unit.dart
│   ├── seller_trust_unit.dart
│   └── validators_unit.dart
├── widget/                       # Widget tests (screens & components)
│   ├── countdown_timer_widget.dart
│   ├── responsive_widget.dart
│   ├── seller_trust_badge_widget.dart
│   ├── sign_in_screen_widget.dart
│   ├── star_rating_widget.dart
│   ├── thrift_button_widget.dart
│   ├── thrift_display_widget.dart
│   └── thrift_text_field_widget.dart
└── integration_test/             # Integration tests (organized by feature)
    ├── auth_test.dart            # Signup, role selection, session persistence
    ├── buyer_checkout_test.dart  # Multi-seller cart, Davao delivery address, shipping fee, stock clamp
    ├── seller_listing_test.dart  # Fixed vs auction listings, seller trust & verification
    ├── auction_test.dart         # Auction countdown, bidding increments, outbid lifecycle
    ├── payment_test.dart         # PayMongo checkout, centavos conversion, order status, inspection
    ├── chat_messaging_test.dart  # Buyer-seller chat, offer messages, unread indicators, model parsing
    ├── notification_inbox_test.dart # Audience filtering, read/unread state, appeal routing
    ├── order_tracking_test.dart  # Shipment lifecycle, rider privacy, delivery failures, status flags
    ├── trust_safety_test.dart    # Reviews, community reports, return shipment lifecycle
    └── profile_account_test.dart # Profile edit, account mode switching, seller profile parsing
```

---

## 4. Integration Tests by Feature

| Feature | Test File | Covers |
| :--- | :--- | :--- |
| **Auth** | `auth_test.dart` | Sign-up form, role selection, session persistence, logout |
| **Buyer** | `buyer_checkout_test.dart` | Multi-item cart, delivery address, shipping fees, stock clamp |
| **Seller** | `seller_listing_test.dart` | Fixed/auction listing creation, verification gate, trust labels |
| **Auction** | `auction_test.dart` | Bidding cycle, increment validation, outbid/won states, countdown |
| **Payment** | `payment_test.dart` | PayMongo flow, centavos conversion, order status progression |
| **Chat** | `chat_messaging_test.dart` | Text/offer messages, ChatModel parsing, unread indicators |
| **Notifications** | `notification_inbox_test.dart` | Audience filtering by account mode, read state, appeal routing |
| **Order Tracking** | `order_tracking_test.dart` | Delivery lifecycle, rider privacy, failure summaries, status flags |
| **Trust & Safety** | `trust_safety_test.dart` | Leave review, report user, ReviewModel/CommunityReportModel, returns |
| **Profile** | `profile_account_test.dart` | Profile edit, UserModel/SellerProfile parsing, account mode resolution |

---

## 5. Running the Tests

To run the complete QA suite:
```bash
flutter test test/qa/qa_suite_test.dart
```

To run individual test types:
```bash
# Run only Unit Tests
flutter test test/qa/qa_suite_test.dart --plain-name "[UNIT TEST]"

# Run only Widget Tests
flutter test test/qa/qa_suite_test.dart --plain-name "[WIDGET TEST]"

# Run only Integration Tests
flutter test test/qa/qa_suite_test.dart --plain-name "[INTEGRATION TEST]"
```

To run individual integration tests directly:
```bash
flutter test test/qa/integration_test/auth_test.dart
flutter test test/qa/integration_test/buyer_checkout_test.dart
flutter test test/qa/integration_test/seller_listing_test.dart
flutter test test/qa/integration_test/auction_test.dart
flutter test test/qa/integration_test/payment_test.dart
flutter test test/qa/integration_test/chat_messaging_test.dart
flutter test test/qa/integration_test/notification_inbox_test.dart
flutter test test/qa/integration_test/order_tracking_test.dart
flutter test test/qa/integration_test/trust_safety_test.dart
flutter test test/qa/integration_test/profile_account_test.dart
```

