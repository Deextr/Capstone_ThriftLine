import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_order_report_timeline.dart';
import 'package:thriftline/features/admin/data/admin_report_decision_content.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_order_report_detail_widgets.dart';
import 'package:thriftline/models/community_report_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';

CommunityReportModel _report({
  String status = kAdminReportOpenStatus,
  DateTime? createdAt,
}) {
  return CommunityReportModel(
    id: '11111111-1111-4111-8111-111111111111',
    reporterId: '22222222-2222-4222-8222-222222222222',
    reportedUserId: '33333333-3333-4333-8333-333333333333',
    reportedUsername: 'seller1',
    reportedDisplayName: 'Seller One',
    reporterUsername: 'buyer1',
    reporterDisplayName: 'Buyer One',
    reporterRole: 'buyer',
    orderId: '44444444-4444-4444-8444-444444444444',
    orderNumber: '10042',
    category: 'item_not_as_described',
    details: 'Item color does not match listing photos.',
    status: status,
    createdAt: createdAt ?? DateTime(2026, 3, 1, 10),
  );
}

OrderModel _order({
  OrderStatus status = OrderStatus.preparing,
  DateTime? createdAt,
}) {
  final at = createdAt ?? DateTime.now().subtract(const Duration(days: 5));
  return OrderModel(
    id: '44444444-4444-4444-8444-444444444444',
    orderNumber: '10042',
    productId: 'prod-1',
    buyerId: '22222222-2222-4222-8222-222222222222',
    sellerId: '33333333-3333-4333-8333-333333333333',
    productTitle: 'Vintage jacket',
    productImage: 'https://example.com/jacket.jpg',
    sellerName: 'Seller One',
    buyerName: 'Buyer One',
    buyerAvatar: '',
    amount: 500,
    shippingFee: 50,
    platformFee: 25,
    total: 575,
    status: status,
    paymentMethod: PaymentMethod.paymongo,
    deliveryMethod: DeliveryMethod.standard,
    shippingAddress: '123 Test St',
    createdAt: at,
    paymentStatus: 'paid',
    quantity: 1,
  );
}

void main() {
  group('buildEvidenceRequestInstruction', () {
    test('formats selected evidence types', () {
      final msg = buildEvidenceRequestInstruction(
        selectedTypeLabels: ['Product photos', 'Delivery receipt'],
        intro:
            'Please provide the following evidence to continue the investigation',
      );
      expect(msg, contains('Product photos'));
      expect(msg, contains('Delivery receipt'));
      expect(msg.length, greaterThanOrEqualTo(20));
    });
  });

  group('buildAdminOrderReportCaseTimeline', () {
    test('includes order lifecycle and under admin review for open report', () {
      final events = buildAdminOrderReportCaseTimeline(
        report: _report(),
        order: _order(status: OrderStatus.shipped),
      );
      final titles = events.map((e) => e.title).toList();
      expect(titles, contains('Order placed'));
      expect(titles, contains('Payment confirmed'));
      expect(titles, contains('Shipped'));
      expect(titles, contains('Report submitted'));
      expect(titles.last, 'Under admin review');
    });

    test('flags stalled preparing stage', () {
      final events = buildAdminOrderReportCaseTimeline(
        report: _report(),
        order: _order(
          status: OrderStatus.preparing,
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      );
      final preparing = events.firstWhere((e) => e.title == 'Preparing order');
      expect(preparing.emphasisWarning, isTrue);
      expect(preparing.subtitle, isNotNull);
    });

    test('resolved report includes financial outcome step', () {
      final events = buildAdminOrderReportCaseTimeline(
        report: CommunityReportModel(
          id: '11111111-1111-4111-8111-111111111111',
          reporterId: 'a',
          reportedUserId: 'b',
          reportedUsername: 's',
          reportedDisplayName: 'S',
          category: 'failure_to_ship',
          details: 'x',
          status: 'resolved',
          resolutionFinancial: 'refund_buyer',
          createdAt: DateTime(2026, 1, 1),
          resolvedAt: DateTime(2026, 1, 2),
        ),
        order: null,
      );
      expect(events.map((e) => e.title), contains('Buyer refunded'));
    });
  });

  group('AdminOrderReportSummaryCard', () {
    testWidgets('shows reason once with status badge', (tester) async {
      final report = _report();
      final parties = AdminOrderReportParties.from(
        report: report,
        order: _order(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminOrderReportSummaryCard(
              report: report,
              parties: parties,
              order: _order(),
            ),
          ),
        ),
      );

      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('Item Not as Described'), findsOneWidget);
    });
  });
}
