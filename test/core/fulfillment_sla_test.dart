import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/fulfillment_sla.dart';
import 'package:thriftline/models/community_report_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/shipment_model.dart';

OrderModel _order({
  OrderStatus status = OrderStatus.paymentConfirmed,
  String paymentStatus = 'paid',
  DateTime? paidAt,
  DateTime? createdAt,
  ShipmentModel? shipment,
}) {
  final created = createdAt ?? DateTime(2026, 10, 1, 8);
  return OrderModel(
    id: 'order-1',
    orderNumber: 'TL-1',
    productId: 'p1',
    buyerId: 'b1',
    sellerId: 's1',
    productTitle: 'Jacket',
    productImage: '',
    sellerName: 'Shop',
    buyerName: 'Buyer',
    buyerAvatar: '',
    amount: 100,
    shippingFee: 80,
    platformFee: 2,
    total: 182,
    status: status,
    paymentMethod: PaymentMethod.paymongo,
    deliveryMethod: DeliveryMethod.standard,
    shippingAddress: 'Davao',
    createdAt: created,
    paymentStatus: paymentStatus,
    paidAt: paidAt ?? created,
    shipment: shipment,
  );
}

void main() {
  group('fulfillment SLA', () {
    test('hides report until 48 hours after payment', () {
      final paid = DateTime(2026, 10, 10, 12);
      final order = _order(paidAt: paid);
      final view = fulfillmentSlaForOrder(
        order,
        now: paid.add(const Duration(hours: 47)),
      );
      expect(view.cta, FulfillmentReportCta.waiting);
      expect(view.canSubmitFulfillmentReport, isFalse);
      expect(view.stuckPreparing, isTrue);
    });

    test('unlocks report after 48 hours while still preparing', () {
      final paid = DateTime(2026, 10, 10, 12);
      final order = _order(paidAt: paid);
      final view = fulfillmentSlaForOrder(
        order,
        now: paid.add(const Duration(hours: 48)),
      );
      expect(view.cta, FulfillmentReportCta.ready);
      expect(view.canSubmitFulfillmentReport, isTrue);
    });

    test('flags admin delayed after 72 hours', () {
      final paid = DateTime(2026, 10, 10, 12);
      final view = fulfillmentSlaForOrder(
        _order(paidAt: paid),
        now: paid.add(const Duration(hours: 73)),
      );
      expect(view.delayedForAdmin, isTrue);
      expect(view.autoCancelAt, paid.add(const Duration(hours: 72)));
    });

    test('hides fulfillment report after rider handoff', () {
      final paid = DateTime(2026, 10, 8);
      final order = _order(
        paidAt: paid,
        shipment: ShipmentModel(
          id: 'sh1',
          orderId: 'order-1',
          deliveryStatus: DeliveryStatus.riderAssigned,
          riderAssignedAt: paid.add(const Duration(hours: 2)),
        ),
      );
      final view = fulfillmentSlaForOrder(
        order,
        now: paid.add(const Duration(days: 3)),
      );
      expect(view.cta, FulfillmentReportCta.hidden);
      expect(isOrderStuckPreparing(order), isFalse);
    });

    test('shows under review when an open report exists', () {
      final paid = DateTime(2026, 10, 8);
      final view = fulfillmentSlaForOrder(
        _order(paidAt: paid),
        now: paid.add(const Duration(days: 3)),
        report: CommunityReportModel(
          id: 'r1',
          reporterId: 'b1',
          reportedUserId: 's1',
          reportedUsername: 'shop',
          reportedDisplayName: 'Shop',
          category: 'seller_not_processing_order',
          details: 'Still preparing after two days.',
          status: 'under_review',
          createdAt: paid.add(const Duration(hours: 50)),
        ),
      );
      expect(view.cta, FulfillmentReportCta.underReview);
    });

    test('parses paidAt from nested payments.updated_at', () {
      final stamp = DateTime.parse('2026-10-10T04:00:00.000Z');
      final at = paidAtFromPaymentsRow({
        'payments': [
          {'payment_status': 'paid', 'updated_at': stamp.toIso8601String()},
        ],
      });
      expect(at, stamp);
    });
  });
}
