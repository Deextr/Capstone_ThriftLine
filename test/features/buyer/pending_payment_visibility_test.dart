import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/order_query.dart';
import 'package:thriftline/models/order_model.dart';

OrderModel _order({
  required String id,
  required String status,
  List<Map<String, dynamic>>? payments,
  String? auctionId,
  String orderType = 'fixed_price',
  DateTime? createdAt,
}) {
  return OrderModel.fromSupabase({
    'order_id': id,
    'order_number': 'TL-$id',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-1',
    'order_status': status,
    'order_type': orderType,
    if (auctionId != null) 'auction_id': auctionId,
    if (payments != null) 'payments': payments,
    'subtotal': 1000,
    'shipping_fee': 80,
    'platform_fee': 20,
    'total_amount': 1100,
    'created_at':
        (createdAt ?? DateTime.now().subtract(const Duration(minutes: 10)))
            .toUtc()
            .toIso8601String(),
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

    test('lists fixed-price pending checkouts for recovery', () {
      final pendingFixed = _order(id: 'pending', status: 'pending');
      expect(pendingFixed.needsBuyerPayment, isTrue);
      expect(pendingFixed.showsAsAwaitingPayment, isTrue);
      expect(buyerPendingPayments([pendingFixed]).map((o) => o.id), [
        'pending',
      ]);
    });

    test('lists only live auction wins and fixed reservations for pending', () {
      final pendingAuction = _order(
        id: 'pending-auction',
        status: 'pending',
        auctionId: 'auction-1',
        orderType: 'auction',
      );
      final pendingFixed = _order(id: 'pending-fixed', status: 'pending');
      final paid = _order(id: 'paid', status: 'paid');
      final voided = _order(id: 'voided', status: 'cancelled');
      final expired = _order(
        id: 'expired',
        status: 'pending',
        auctionId: 'auction-2',
        orderType: 'auction',
        payments: [
          {'payment_status': 'expired'},
        ],
      );
      final staleFixed = _order(
        id: 'stale-fixed',
        status: 'pending',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      expect(
        buyerPendingPayments([
          pendingAuction,
          pendingFixed,
          paid,
          voided,
          expired,
          staleFixed,
        ]).map((o) => o.id).toSet(),
        {'pending-auction', 'pending-fixed'},
      );
    });
  });
}
