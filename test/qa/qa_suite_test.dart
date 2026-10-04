// ThriftLine QA suite — single entry point for all QA unit, widget and integration tests.
//
// Run everything:
//   flutter test test/qa
// Run one test type:
//   flutter test test/qa --plain-name "[UNIT TEST]"
//   flutter test test/qa --plain-name "[WIDGET TEST]"
//   flutter test test/qa --plain-name "[INTEGRATION TEST]"
//
// Or run individual integration tests directly:
//   flutter test test/qa/integration_test/auth_test.dart
//   flutter test test/qa/integration_test/buyer_checkout_test.dart
//   flutter test test/qa/integration_test/seller_listing_test.dart
//   flutter test test/qa/integration_test/auction_test.dart
//   flutter test test/qa/integration_test/payment_test.dart
//   flutter test test/qa/integration_test/chat_messaging_test.dart
//   flutter test test/qa/integration_test/notification_inbox_test.dart
//   flutter test test/qa/integration_test/order_tracking_test.dart
//   flutter test test/qa/integration_test/trust_safety_test.dart
//   flutter test test/qa/integration_test/profile_account_test.dart
//
// See test/qa/README.md for the status log format and coverage notes.

import 'package:flutter_test/flutter_test.dart';

import 'integration_test/auction_test.dart';
import 'integration_test/auth_test.dart';
import 'integration_test/buyer_checkout_test.dart';
import 'integration_test/chat_messaging_test.dart';
import 'integration_test/notification_inbox_test.dart';
import 'integration_test/order_tracking_test.dart';
import 'integration_test/payment_test.dart';
import 'integration_test/profile_account_test.dart';
import 'integration_test/seller_listing_test.dart';
import 'integration_test/trust_safety_test.dart';
import 'support/qa_reporter.dart';
import 'unit/ai_search_parser_unit.dart';
import 'unit/enums_unit.dart';
import 'unit/formatters_unit.dart';
import 'unit/helpers_unit.dart';
import 'unit/models_unit.dart';
import 'unit/money_and_stock_unit.dart';
import 'unit/ph_phone_unit.dart';
import 'unit/providers_unit.dart';
import 'unit/rider_privacy_unit.dart';
import 'unit/seller_trust_unit.dart';
import 'unit/validators_unit.dart';
import 'widget/countdown_timer_widget.dart';
import 'widget/responsive_widget.dart';
import 'widget/seller_trust_badge_widget.dart';
import 'widget/sign_in_screen_widget.dart';
import 'widget/star_rating_widget.dart';
import 'widget/thrift_button_widget.dart';
import 'widget/thrift_display_widget.dart';
import 'widget/thrift_text_field_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(QaReporter.printFinalReport);

  // ── Unit tests: individual functions/classes (flutter_test) ──────────────
  qaSection(QaTestType.unit, () {
    validatorsUnitTests();
    formattersUnitTests();
    phPhoneUnitTests();
    moneyAndStockUnitTests();
    aiSearchParserUnitTests();
    riderPrivacyUnitTests();
    sellerTrustUnitTests();
    enumsUnitTests();
    modelsUnitTests();
    helpersUnitTests();
    providersUnitTests();
  });

  // ── Widget tests: individual screens/widgets (flutter_test) ──────────────
  qaSection(QaTestType.widget, () {
    thriftButtonWidgetTests();
    thriftTextFieldWidgetTests();
    thriftDisplayWidgetTests();
    starRatingWidgetTests();
    countdownTimerWidgetTests();
    sellerTrustBadgeWidgetTests();
    responsiveWidgetTests();
    signInScreenWidgetTests();
  });

  // ── Integration tests: end-to-end flows (integration_test) ───────────────
  // Organized by feature for clear traceability.
  qaSection(QaTestType.integration, () {
    // Auth
    authIntegrationTests();
    // Buyer
    buyerCheckoutIntegrationTests();
    // Seller
    sellerListingIntegrationTests();
    // Auction & Bidding
    auctionIntegrationTests();
    // Payment & Settlement
    paymentIntegrationTests();
    // Chat & Messaging
    chatMessagingIntegrationTests();
    // Notification Inbox
    notificationIntegrationTests();
    // Order Tracking & Delivery
    orderTrackingIntegrationTests();
    // Trust & Safety (Reviews, Reports, Returns)
    trustSafetyIntegrationTests();
    // Profile & Account Mode
    profileAccountIntegrationTests();
  });
}
