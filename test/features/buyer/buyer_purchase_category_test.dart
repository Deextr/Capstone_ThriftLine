import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/buyer_purchase_category.dart';
import 'package:thriftline/models/order_model.dart';

OrderModel _base({
  required String id,
  String status = 'paid',
  String? auctionId,
  String orderType = 'fixed_price',
  List<Map<String, dynamic>>? payments,
  Map<String, dynamic>? shipment,
  DateTime? paymentDueAt,
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
    if (shipment != null) 'shipment': shipment,
    if (paymentDueAt != null)
      'payment_due_at': paymentDueAt.toUtc().toIso8601String(),
    'subtotal': 1000,
    'shipping_fee': 80,
    'platform_fee': 20,
    'total_amount': 1100,
    'created_at': '2026-09-24T02:00:00Z',
  });
}

void main() {
  group('orderIncludedInMyPurchases', () {
    test('excludes unpaid fixed-price checkouts', () {
      final pending = _base(id: 'p', status: 'pending');
      expect(orderIncludedInMyPurchases(pending), isFalse);
    });

    test('includes auction awaiting payment', () {
      final auction = _base(
        id: 'a',
        status: 'pending',
        auctionId: 'auc-1',
        orderType: 'auction',
        paymentDueAt: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(orderIncludedInMyPurchases(auction), isTrue);
      expect(buyerPurchaseCategory(auction), BuyerPurchaseCategory.toPay);
    });
  });

  group('buyerPurchaseCategory', () {
    test('maps expired auction win to cancelled', () {
      final expired = _base(
        id: 'exp',
        status: 'pending',
        auctionId: 'auc-2',
        orderType: 'auction',
        payments: [
          {'payment_status': 'expired'},
        ],
      );
      expect(buyerPurchaseCategory(expired), BuyerPurchaseCategory.cancelled);
    });

    test('maps paid order without shipment to payment confirmed', () {
      final paid = _base(id: 'paid', status: 'paid');
      expect(
        buyerPurchaseCategory(paid),
        BuyerPurchaseCategory.paymentConfirmed,
      );
    });

    test('maps rider assigned to payment confirmed', () {
      final preparing = _base(
        id: 'prep',
        status: 'paid',
        shipment: {
          'delivery_status': 'rider_assigned',
        },
      );
      expect(
        buyerPurchaseCategory(preparing),
        BuyerPurchaseCategory.paymentConfirmed,
      );
    });

    test('maps picked up to payment confirmed', () {
      final picked = _base(
        id: 'pick',
        status: 'shipped',
        shipment: {
          'delivery_status': 'picked_up',
        },
      );
      expect(
        buyerPurchaseCategory(picked),
        BuyerPurchaseCategory.paymentConfirmed,
      );
    });

    test('maps out for delivery to to receive', () {
      final out = _base(
        id: 'out',
        status: 'shipped',
        shipment: {
          'delivery_status': 'out_for_delivery',
        },
      );
      expect(buyerPurchaseCategory(out), BuyerPurchaseCategory.toReceive);
    });

    test('maps inspection period to to receive', () {
      final inspect = _base(
        id: 'insp',
        status: 'delivered',
        shipment: {
          'delivery_status': 'inspection_period',
        },
      );
      expect(buyerPurchaseCategory(inspect), BuyerPurchaseCategory.toReceive);
    });

    test('maps disputed order to return/refund', () {
      final disputed = _base(id: 'disp', status: 'disputed');
      expect(
        buyerPurchaseCategory(disputed),
        BuyerPurchaseCategory.returnRefund,
      );
    });

    test('maps completed order to completed tab', () {
      final done = _base(id: 'done', status: 'completed');
      expect(buyerPurchaseCategory(done), BuyerPurchaseCategory.completed);
    });
  });

  group('ordersForPurchaseCategory', () {
    test('all tab includes every visible order', () {
      final paid = _base(id: 'a', status: 'paid');
      final done = _base(id: 'b', status: 'completed');
      final list = ordersForPurchaseCategory(
        [paid, done],
        BuyerPurchaseCategory.all,
      );
      expect(list.length, 2);
    });

    test('keeps seller orders separate in lists', () {
      final sellerA = _base(id: 'a', status: 'paid');
      final sellerB = OrderModel.fromSupabase({
        'order_id': 'b',
        'order_number': 'TL-b',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-2',
        'order_status': 'paid',
        'subtotal': 500,
        'shipping_fee': 80,
        'platform_fee': 10,
        'total_amount': 590,
        'created_at': '2026-09-24T02:00:00Z',
      });
      final list = ordersForPurchaseCategory(
        [sellerA, sellerB],
        BuyerPurchaseCategory.paymentConfirmed,
      );
      expect(list.length, 2);
      expect(list.map((o) => o.sellerId).toSet(), {'seller-1', 'seller-2'});
    });
  });

  group('defaultPurchaseCategory', () {
    test('defaults to all', () {
      expect(defaultPurchaseCategory(), BuyerPurchaseCategory.all);
    });
  });
}
