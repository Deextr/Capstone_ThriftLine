import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_orders_service.dart';
import 'package:thriftline/features/admin/domain/admin_buyer_refund.dart';
import 'package:thriftline/core/utils/fulfillment_sla.dart';
import 'package:thriftline/features/admin/domain/admin_order_filter_rules.dart';
import 'package:thriftline/features/admin/domain/admin_order_management.dart';

void main() {
  group('adminPaymentStatusLabel', () {
    test('maps known payment statuses', () {
      expect(adminPaymentStatusLabel('paid'), 'Paid');
      expect(adminPaymentStatusLabel('pending'), 'Payment pending');
      expect(adminPaymentStatusLabel('refunded'), 'Refunded');
      expect(adminPaymentStatusLabel('failed'), 'Payment failed');
      expect(adminPaymentStatusLabel('expired'), 'Checkout expired');
    });
  });

  group('adminBuyerRefundNeedsAdminAction', () {
    test('only manual_required opens buyer refunds workflow', () {
      expect(
        adminBuyerRefundNeedsAdminAction(refundState: 'manual_required'),
        isTrue,
      );
      expect(
        adminBuyerRefundNeedsAdminAction(refundState: 'provider_pending'),
        isFalse,
      );
      expect(
        adminBuyerRefundNeedsAdminAction(refundState: 'succeeded'),
        isFalse,
      );
    });
  });

  group('adminUnifiedOrderStatus', () {
    test('cancelled with paid payment needs review', () {
      final status = adminUnifiedOrderStatus(
        orderStatusDb: 'cancelled',
        paymentStatus: 'paid',
      );
      expect(status.label, contains('Payment review'));
    });

    test('cancelled unpaid shows cancelled', () {
      final status = adminUnifiedOrderStatus(
        orderStatusDb: 'cancelled',
        paymentStatus: 'pending',
      );
      expect(status.label, 'Cancelled');
    });

    test('refunded payment shows refunded context', () {
      final status = adminUnifiedOrderStatus(
        orderStatusDb: 'paid',
        paymentStatus: 'refunded',
      );
      expect(status.label, 'Refunded');
    });

    test('manual_required escrow is not labelled completed refund', () {
      final status = adminUnifiedOrderStatus(
        orderStatusDb: 'paid',
        paymentStatus: 'paid',
        escrowStatus: 'refunded',
        refundState: 'manual_required',
      );
      expect(status.label, 'Refund needs action');
      expect(status.badgeKey, isNot('refunded'));
    });

    test('escrow manual_completed counts as refunded presentation', () {
      final status = adminUnifiedOrderStatus(
        orderStatusDb: 'cancelled',
        paymentStatus: 'paid',
        escrowStatus: 'refunded',
        refundState: 'manual_completed',
      );
      expect(status.label, contains('Refunded'));
    });
  });

  group('adminOrderFilterRules', () {
    final paidAt = DateTime.utc(2026, 1, 1, 12);

    test('fulfillment overdue when stuck preparing past 72h', () {
      final at = paidAt.add(kFulfillmentAdminDelayed);
      expect(
        adminOrderFulfillmentOverdue(
          stuckPreparing: true,
          paidAt: paidAt,
          now: at,
        ),
        isTrue,
      );
      expect(
        adminOrderFulfillmentOverdue(
          stuckPreparing: true,
          paidAt: paidAt,
          now: paidAt.add(
            kFulfillmentAdminDelayed - const Duration(seconds: 1),
          ),
        ),
        isFalse,
      );
    });

    test('shipped orders are not overdue when not stuck preparing', () {
      expect(
        adminOrderFulfillmentOverdue(
          stuckPreparing: false,
          paidAt: paidAt.subtract(const Duration(days: 10)),
          now: paidAt,
        ),
        isFalse,
      );
    });

    test('refund classification matches buyer refunds module', () {
      expect(
        adminOrderRefundNeedsAdminAction(
          escrowStatus: 'refunded',
          refundState: 'manual_required',
        ),
        isTrue,
      );
      expect(
        adminOrderRefundFinanciallyCompleted(
          paymentStatus: 'paid',
          escrowStatus: 'refunded',
          refundState: 'manual_required',
        ),
        isFalse,
      );
      expect(
        adminOrderRefundFinanciallyCompleted(
          paymentStatus: 'paid',
          escrowStatus: 'refunded',
          refundState: 'succeeded',
        ),
        isTrue,
      );
      expect(
        adminOrderRefundFinanciallyCompleted(
          paymentStatus: 'refunded',
          escrowStatus: 'held',
          refundState: null,
        ),
        isTrue,
      );
      expect(
        adminOrderRefundFinanciallyCompleted(
          paymentStatus: 'paid',
          escrowStatus: 'refunded',
          refundState: 'provider_pending',
        ),
        isFalse,
      );
    });

    test('AdminOrderRow uses server SLA flag for delayed badge', () {
      final row = AdminOrderRow.fromJson({
        'order_id': '11111111-1111-1111-1111-111111111111',
        'order_number': 'TL-DELAY',
        'order_type': 'fixed_price',
        'total_amount': 500,
        'order_status': 'shipped',
        'created_at': '2026-01-01T10:00:00.000Z',
        'buyer': {'full_name': 'Buyer A'},
        'seller': {'full_name': 'Seller B'},
        'payments': [
          {'payment_status': 'paid', 'updated_at': '2025-01-01T10:00:00.000Z'},
        ],
        'admin_order_sla_flags': {'fulfillment_overdue': false},
      });
      expect(row.isFulfillmentDelayed, isFalse);

      final delayed = AdminOrderRow.fromJson({
        'order_id': '22222222-2222-2222-2222-222222222222',
        'order_number': 'TL-LATE',
        'order_type': 'fixed_price',
        'total_amount': 500,
        'order_status': 'paid',
        'created_at': '2026-01-01T10:00:00.000Z',
        'buyer': {'full_name': 'Buyer A'},
        'seller': {'full_name': 'Seller B'},
        'payments': [
          {'payment_status': 'paid', 'updated_at': '2026-01-01T10:00:00.000Z'},
        ],
        'admin_order_sla_flags': {'fulfillment_overdue': true},
      });
      expect(delayed.isFulfillmentDelayed, isTrue);
    });
  });

  group('adminOrderKindFromRow', () {
    test('uses order_type auction', () {
      expect(
        adminOrderKindFromRow(orderType: 'auction', auctionId: null),
        AdminOrderKind.auction,
      );
    });

    test('uses auction_id when type missing', () {
      expect(
        adminOrderKindFromRow(orderType: 'fixed_price', auctionId: 'abc-123'),
        AdminOrderKind.auction,
      );
    });
  });

  group('buildAdminOrderTimeline', () {
    test('includes payment and escrow timestamps only', () {
      final events = buildAdminOrderTimeline(
        payments: [
          {
            'created_at': '2026-01-01T10:00:00.000Z',
            'updated_at': '2026-01-01T10:05:00.000Z',
            'payment_status': 'paid',
            'paymongo_channel': 'gcash',
          },
        ],
        escrow: {
          'held_at': '2026-01-01T10:06:00.000Z',
          'released_at': '2026-01-02T08:00:00.000Z',
          'release_reason': 'Delivery verified',
        },
      );
      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.first.title, contains('Escrow'));
    });
  });

  group('AdminOrderRow', () {
    test('prefers paid payment status when multiple rows exist', () {
      final row = AdminOrderRow.fromJson({
        'order_id': '11111111-1111-1111-1111-111111111111',
        'order_number': 'TL-TEST',
        'order_type': 'fixed_price',
        'total_amount': 500,
        'order_status': 'paid',
        'created_at': '2026-01-01T10:00:00.000Z',
        'buyer': {'full_name': 'Buyer A'},
        'seller': {'full_name': 'Seller B'},
        'payments': [
          {'payment_status': 'failed'},
          {'payment_status': 'paid'},
        ],
      });
      expect(row.paymentStatus, 'paid');
      expect(row.orderKind, AdminOrderKind.fixedPrice);
      expect(row.unifiedStatus.label, isNotEmpty);
    });
  });

  group('looksLikeUuid', () {
    test('detects uuid-shaped search terms', () {
      expect(looksLikeUuid('11111111-1111-1111-1111-111111111111'), isTrue);
      expect(looksLikeUuid('TL-260101-ABC'), isFalse);
    });
  });
}
