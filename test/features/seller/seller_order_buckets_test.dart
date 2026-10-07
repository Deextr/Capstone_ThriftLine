import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/features/seller/data/seller_order_buckets.dart';
import 'package:thriftline/models/order_model.dart';

void main() {
  group('shortPersonName', () {
    test('keeps a single name and shortens a full name', () {
      expect(shortPersonName('Dexter Ramos'), 'Dexter R.');
      expect(shortPersonName('Maria'), 'Maria');
      expect(shortPersonName('  '), 'Buyer');
    });
  });

  group('formatCompactDate', () {
    test('uses today for the current local day', () {
      final now = DateTime(2026, 9, 13, 18);
      expect(formatCompactDate(DateTime(2026, 9, 13, 9), now: now), 'today');
      expect(formatCompactDate(DateTime(2026, 9, 12, 9), now: now), 'Sep 12');
    });
  });

  group('seller order buckets', () {
    test('counts match the same filters used by each tab list', () {
      final orders = [
        _order(id: 'pending-fixed', status: 'pending'),
        _order(
          id: 'pending-auction',
          status: 'pending',
          auctionId: 'auction-1',
        ),
        _order(id: 'to-ship-1', status: 'paid'),
        _order(
          id: 'to-ship-2',
          status: 'paid',
          shipment: {'delivery_status': 'seller_preparing'},
        ),
        _order(
          id: 'shipped',
          status: 'shipped',
          shipment: {'delivery_status': 'out_for_delivery'},
        ),
        _order(id: 'done-1', status: 'completed'),
        _order(id: 'done-2', status: 'completed'),
        _order(id: 'done-3', status: 'completed'),
        _order(id: 'done-4', status: 'completed'),
        _order(id: 'done-5', status: 'completed'),
        _order(id: 'failed-checkout', status: 'cancelled', payment: 'failed'),
      ];

      expect(sellerOrderCount(orders, SellerOrderBucket.pendingPayment), 1);
      expect(
        sellerOrdersInBucket(
          orders,
          SellerOrderBucket.pendingPayment,
        ).map((o) => o.id),
        ['pending-auction'],
      );
      expect(sellerOrderCount(orders, SellerOrderBucket.toShip), 2);
      expect(sellerOrderCount(orders, SellerOrderBucket.shipped), 1);
      expect(sellerOrderCount(orders, SellerOrderBucket.completed), 5);
      expect(sellerOrderCount(orders, SellerOrderBucket.cancelled), 0);

      expect(
        sellerOrdersInBucket(orders, SellerOrderBucket.toShip).map((o) => o.id),
        ['to-ship-1', 'to-ship-2'],
      );
      expect(
        sellerOrdersInBucket(
          orders,
          SellerOrderBucket.shipped,
        ).map((o) => o.id),
        ['shipped'],
      );
    });

    test('failed unpaid checkouts never appear in seller buckets', () {
      final order = _order(
        id: 'failed',
        status: 'cancelled',
        payment: 'expired',
      );
      expect(order.isFailedCheckout, isTrue);
      expect(sellerOrderBucketFor(order), isNull);
      for (final bucket in SellerOrderBucket.values) {
        expect(orderMatchesSellerBucket(order, bucket), isFalse);
      }
    });

    test('abandoned fixed-price voids are hidden from seller buckets', () {
      final order = _order(
        id: 'abandoned',
        status: 'cancelled',
        payment: 'pending',
      );
      expect(order.isAbandonedCheckout, isTrue);
      expect(sellerOrderBucketFor(order), isNull);
    });

    test('cancelled without payment row is hidden for fixed-price sellers', () {
      final order = _order(id: 'void-unpaid', status: 'cancelled');
      expect(sellerOrderBucketFor(order), isNull);
    });

    test('paid preparing orders stay in To Ship, not Shipped', () {
      final order = _order(
        id: 'paid',
        status: 'paid',
        shipment: {'delivery_status': 'rider_assigned'},
      );
      expect(sellerOrderBucketFor(order), SellerOrderBucket.toShip);
      expect(sellerOrderChip(order).label, 'To Ship');
    });

    test('out for delivery moves from To Ship to Shipped', () {
      final order = _order(
        id: 'out',
        status: 'shipped',
        shipment: {'delivery_status': 'out_for_delivery'},
      );
      expect(sellerOrderBucketFor(order), SellerOrderBucket.shipped);
      expect(sellerOrderChip(order).label, 'Shipped');
      expect(order.isToShip, isFalse);
    });

    test('completed orders leave the Shipped tab', () {
      final order = _order(
        id: 'done',
        status: 'completed',
        shipment: {'delivery_status': 'completed'},
      );
      expect(sellerOrderBucketFor(order), SellerOrderBucket.completed);
      expect(order.isShippedTab, isFalse);
    });

    test('fixed-price unpaid checkout is hidden from seller buckets', () {
      final order = _order(id: 'checkout', status: 'pending');
      expect(order.isPaymentPending, isTrue);
      expect(order.isAuctionObligation, isFalse);
      expect(sellerOrderBucketFor(order), isNull);
    });

    test('each visible order belongs to exactly one bucket', () {
      final orders = [
        _order(id: 'pending', status: 'pending', auctionId: 'auction-2'),
        _order(id: 'paid', status: 'paid'),
        _order(
          id: 'out',
          status: 'shipped',
          shipment: {'delivery_status': 'out_for_delivery'},
        ),
        _order(
          id: 'inspect',
          status: 'delivered',
          shipment: {'delivery_status': 'inspection_period'},
        ),
        _order(id: 'done', status: 'completed'),
        _order(id: 'cancelled', status: 'cancelled', auctionId: 'auction-1'),
      ];
      for (final order in orders) {
        final matches = SellerOrderBucket.values
            .where((bucket) => orderMatchesSellerBucket(order, bucket))
            .toList();
        expect(matches, hasLength(1), reason: order.id);
      }
    });
  });
}

OrderModel _order({
  required String id,
  required String status,
  String? payment,
  String? auctionId,
  Map<String, dynamic>? shipment,
}) {
  return OrderModel.fromSupabase({
    'order_id': id,
    'order_number': 'TL-$id',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-1',
    'order_status': status,
    'subtotal': 500,
    'shipping_fee': 40,
    'platform_fee': 10,
    'total_amount': 550,
    'created_at': '2026-09-13T02:00:00Z',
    if (auctionId != null) 'auction_id': auctionId,
    if (payment != null)
      'payments': [
        {'payment_status': payment},
      ],
    if (shipment != null) 'shipment': {'shipment_id': 'ship-$id', ...shipment},
  });
}
