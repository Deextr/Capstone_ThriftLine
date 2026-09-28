import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/order_query.dart';
import 'package:thriftline/models/order_model.dart';

OrderModel _order({
  required String id,
  required String status,
  List<Map<String, dynamic>>? payments,
}) {
  return OrderModel.fromSupabase({
    'order_id': id,
    'order_number': 'TL-$id',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-1',
    'order_status': status,
    if (payments != null) 'payments': payments,
    'subtotal': 1000,
    'shipping_fee': 80,
    'platform_fee': 20,
    'total_amount': 1100,
    'created_at': '2026-09-24T02:00:00Z',
  });
}

void main() {
  group('buyer awaiting payment visibility', () {
    test('keeps unpaid checkouts out of history and tracking', () {
      final pending = _order(id: 'pending', status: 'pending');
      expect(pending.needsBuyerPayment, isTrue);
      expect(pending.showsInPurchaseHistory, isFalse);
      expect(pending.isTrackable, isFalse);
    });

    test('lists only live unpaid checkouts for To Pay', () {
      final pending = _order(id: 'pending', status: 'pending');
      final paid = _order(id: 'paid', status: 'paid');
      final voided = _order(id: 'voided', status: 'cancelled');
      final expired = _order(
        id: 'expired',
        status: 'pending',
        payments: [
          {'payment_status': 'expired'},
        ],
      );

      expect(
        buyerAwaitingPayment([pending, paid, voided, expired]).map((o) => o.id),
        ['pending'],
      );
    });
  });
}
