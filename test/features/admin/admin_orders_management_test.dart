import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_orders_service.dart';
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
