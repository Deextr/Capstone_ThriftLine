import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_totals.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';

void main() {
  group('checkout totals', () {
    test('counts unique sellers and charges 80 each', () {
      expect(checkoutSellerCount(['a', 'a', 'b', null, '']), 2);
      expect(checkoutShippingFee(0), 0);
      expect(checkoutShippingFee(1), 80);
      expect(checkoutShippingFee(3), 240);
    });

    test('platform fee is 2 percent rounded to cents', () {
      expect(checkoutPlatformFee(1000), 20);
      expect(checkoutPlatformFee(99), 1.98);
      expect(checkoutPlatformFee(0), 0);
    });

    test('total is subtotal plus shipping plus fee', () {
      expect(
        checkoutTotal(subtotal: 1000, shippingFee: 80, platformFee: 20),
        1100,
      );
    });
  });

  group('order status mapping', () {
    test('maps foundation and Phase 5 status names', () {
      expect(orderStatusFromDb('pending'), OrderStatus.paymentPending);
      expect(orderStatusFromDb('paid'), OrderStatus.preparing);
      expect(orderStatusFromDb('shipped'), OrderStatus.shipped);
      expect(orderStatusFromDb('delivered'), OrderStatus.delivered);
      expect(orderStatusFromDb('completed'), OrderStatus.delivered);
      expect(orderStatusFromDb('cancelled'), OrderStatus.cancelled);
    });

    test('maps paid to to-ship and does not treat it as payment pending', () {
      expect(orderStatusFromDb('paid'), OrderStatus.preparing);
      expect(orderStatusFromDb('completed'), OrderStatus.delivered);
      final order = OrderModel.fromSupabase({
        'order_id': 'order-paid',
        'order_number': 'TL-3',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'paid',
        'subtotal': 100,
        'shipping_fee': 80,
        'platform_fee': 2,
        'total_amount': 182,
        'created_at': '2026-09-11T02:00:00Z',
      });
      expect(order.isPaymentPending, isFalse);
    });

    test('labels pending payment instead of a fake paid state', () {
      expect(orderStatusLabel(OrderStatus.paymentPending), 'Pending payment');
    });
  });

  group('OrderModel.fromSupabase', () {
    test('uses stored totals and item snapshot, not live product price', () {
      final order = OrderModel.fromSupabase(
        {
          'order_id': '11111111-1111-1111-1111-111111111111',
          'order_number': 'TL-260911-ABCDEF12',
          'buyer_id': 'buyer-1',
          'seller_id': 'seller-1',
          'auction_id': null,
          'order_type': 'fixed_price',
          'order_status': 'pending',
          'subtotal': 1500,
          'shipping_fee': 80,
          'platform_fee': 30,
          'total_amount': 1610,
          'shipping_address': {
            'formatted': 'Juan Dela Cruz, 123 Street, Davao City',
            'street_address': '123 Street',
            'city': 'Davao City',
          },
          'created_at': '2026-09-11T02:00:00Z',
          'items': [
            {
              'order_item_id': 'item-1',
              'product_id': 'prod-1',
              'title': 'Vintage Jacket',
              'image_url': 'https://example.com/j.jpg',
              'size': 'M',
              'unit_price': 1500,
              'quantity': 1,
              'line_total': 1500,
            },
          ],
        },
        seller: {'shop_name': 'Retro Shop'},
      );

      expect(order.id, '11111111-1111-1111-1111-111111111111');
      expect(order.orderNumber, 'TL-260911-ABCDEF12');
      expect(order.sellerName, 'Retro Shop');
      expect(order.amount, 1500);
      expect(order.shippingFee, 80);
      expect(order.platformFee, 30);
      expect(order.total, 1610);
      expect(order.isPaymentPending, isTrue);
      expect(order.source, 'fixed_price');
      expect(order.addressMissing, isFalse);
      expect(order.items.single.unitPrice, 1500);
      expect(order.productTitle, 'Vintage Jacket');
    });

    test('marks empty address snapshots as missing', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-2',
        'order_number': 'TL-2',
        'buyer_id': 'winner-1',
        'seller_id': 'seller-1',
        'auction_id': 'auction-1',
        'source': 'auction',
        'status': 'pending',
        'payment_status': 'pending',
        'subtotal': 400,
        'shipping_fee': 80,
        'platform_fee': 8,
        'total': 488,
        'shipping_address': {},
        'created_at': '2026-09-11T02:00:00Z',
        'order_items': const [],
      });

      expect(order.auctionId, 'auction-1');
      expect(order.source, 'auction');
      expect(order.addressMissing, isTrue);
    });
  });
}
