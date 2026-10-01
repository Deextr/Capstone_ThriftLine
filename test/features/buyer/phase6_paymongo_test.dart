import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/money.dart';
import 'package:thriftline/features/buyer/data/checkout_totals.dart';
import 'package:thriftline/features/buyer/data/paymongo_checkout.dart';
import 'package:thriftline/features/buyer/data/paymongo_return_link.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';

void main() {
  group('phpPesosToCentavos', () {
    test('matches Postgres round(total * 100)', () {
      expect(phpPesosToCentavos(500), 50000);
      expect(phpPesosToCentavos(500.00), 50000);
      expect(phpPesosToCentavos(99.99), 9999);
      expect(phpPesosToCentavos(0), 0);
    });
  });

  group('PaymongoCheckoutResult', () {
    test('parses a hosted checkout URL and ignores a client amount field', () {
      final result = PaymongoCheckoutResult.fromMap({
        'success': true,
        'already_paid': false,
        'checkout_url': 'https://checkout.paymongo.com/cs_test',
        'session_id': 'cs_test',
        'total_amount': 1,
      });
      expect(result.success, isTrue);
      expect(result.alreadyPaid, isFalse);
      expect(result.checkoutUrl, 'https://checkout.paymongo.com/cs_test');
      expect(result.sessionId, 'cs_test');
    });

    test('parses already paid without creating another session', () {
      final result = PaymongoCheckoutResult.fromMap({
        'success': true,
        'already_paid': true,
        'order_id': '11111111-1111-4111-8111-111111111111',
      });
      expect(result.success, isTrue);
      expect(result.alreadyPaid, isTrue);
      expect(result.checkoutUrl, isNull);
    });

    test('parses backend errors for Flutter', () {
      final result = PaymongoCheckoutResult.fromMap({
        'success': false,
        'error': 'Order not found.',
      });
      expect(result.success, isFalse);
      expect(result.error, 'Order not found.');
    });
  });

  group('isSafePaymongoCheckoutUrl', () {
    test('allows only https PayMongo checkout hosts', () {
      expect(
        isSafePaymongoCheckoutUrl('https://checkout.paymongo.com/abc'),
        isTrue,
      );
      expect(isSafePaymongoCheckoutUrl('https://evil.example/pay'), isFalse);
      expect(
        isSafePaymongoCheckoutUrl('http://checkout.paymongo.com/abc'),
        isFalse,
      );
    });
  });

  group('PayMongo reconcile result', () {
    test('expired and failed stop confirming', () {
      expect(
        PaymongoReconcileResult.fromMap({'outcome': 'expired'}).isExpired,
        isTrue,
      );
      expect(
        PaymongoReconcileResult.fromMap({'outcome': 'failed'}).isUnsuccessful,
        isTrue,
      );
      expect(
        PaymongoReconcileResult.fromMap({'outcome': 'paid'}).isPaid,
        isTrue,
      );
      expect(
        PaymongoReconcileResult.fromMap({'outcome': 'pending'}).isPending,
        isTrue,
      );
      expect(
        PaymongoReconcileResult.fromMap({'error': 'network'}).isPending,
        isTrue,
      );
      expect(PaymongoReconcileResult.fromMap(null).isUnsuccessful, isFalse);
    });

    test('does not treat a missing outcome as payment failed', () {
      final result = PaymongoReconcileResult.fromMap({'success': true});
      expect(result.isPending, isTrue);
      expect(result.isPaid, isFalse);
      expect(result.isUnsuccessful, isFalse);
    });

    test(
      'keeps pending when PayMongo is paid but the order is still recording',
      () {
        final result = PaymongoReconcileResult.fromMap({
          'success': true,
          'outcome': 'pending',
          'error':
              'Payment is confirmed at PayMongo and is still being recorded.',
        });
        expect(result.isPending, isTrue);
        expect(result.isPaid, isFalse);
        expect(result.isUnsuccessful, isFalse);
      },
    );
  });

  group('PayMongo channel', () {
    test('accepts only card and gcash', () {
      expect(parsePaymongoChannel('gcash'), 'gcash');
      expect(parsePaymongoChannel('CARD'), 'card');
      expect(parsePaymongoChannel('maya'), isNull);
      expect(parsePaymongoChannel('paymongo'), isNull);
      expect(paymongoChannelLabel('gcash'), 'GCash');
      expect(paymongoChannelLabel('card'), 'Credit / Debit Card');
      expect(paymongoChannelCategory('gcash'), 'E-Wallets');
      expect(paymongoChannelCategory('card'), 'Cards');
    });

    test('rejects a checkout start without a supported channel', () {
      final result = PaymongoCheckoutResult.fromMap({
        'success': false,
        'error': 'Choose Card or GCash.',
      });
      expect(result.success, isFalse);
      expect(result.error, 'Choose Card or GCash.');
    });
  });

  group('PayMongo return link', () {
    test('parses the app scheme and ignores an invalid order id', () {
      final link = PaymongoReturnLink.tryParse(
        Uri.parse(
          'thriftline://paymongo-return?status=success&order_id=11111111-1111-4111-8111-111111111111',
        ),
      );
      expect(link, isNotNull);
      expect(link!.cancelled, isFalse);
      expect(link.appLocation, contains('returned=1'));
      expect(link.appLocation, contains('status=success'));
      expect(
        PaymongoReturnLink.tryParse(
          Uri.parse('thriftline://paymongo-return?status=success&order_id=bad'),
        ),
        isNull,
      );
    });

    test('parses an expired PayMongo return', () {
      final link = PaymongoReturnLink.tryParse(
        Uri.parse(
          'thriftline://paymongo-return?status=expired&order_id=11111111-1111-4111-8111-111111111111',
        ),
      );
      expect(link?.expired, isTrue);
      expect(link?.cancelled, isFalse);
      expect(link?.appLocation, contains('status=expired'));
    });

    test('treats cancel as an unsuccessful checkout return', () {
      final link = PaymongoReturnLink.tryParse(
        Uri.parse(
          'thriftline://paymongo-return?status=cancel&order_id=11111111-1111-4111-8111-111111111111',
        ),
      );
      expect(link?.cancelled, isTrue);
      expect(link?.appLocation, contains('status=cancel'));
    });

    test('parses the hosted https return URL without trusting it as paid', () {
      final link = PaymongoReturnLink.tryParse(
        Uri.parse(
          'https://example.supabase.co/functions/v1/paymongo-return?status=success&order_id=11111111-1111-4111-8111-111111111111',
        ),
      );
      expect(link, isNotNull);
      expect(link!.cancelled, isFalse);
      expect(link.expired, isFalse);
      expect(link.appLocation, contains('returned=1'));
    });
  });

  group('one-seller checkout', () {
    test('picks a stable first seller id', () {
      expect(firstCheckoutSellerId(['b', 'a', 'b']), 'a');
      expect(firstCheckoutSellerId([null, '', 'z']), 'z');
      expect(firstCheckoutSellerId(const []), isNull);
    });
  });

  group('order payment UI state', () {
    test('pending is a technical unpaid state, not a completed purchase', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-pending',
        'order_number': 'TL-1',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'pending',
        'subtotal': 1000,
        'shipping_fee': 80,
        'platform_fee': 20,
        'total_amount': 1100,
        'created_at': '2026-09-11T02:00:00Z',
      });
      expect(order.isPaymentPending, isTrue);
      expect(order.needsBuyerPayment, isTrue);
      expect(order.showsInPurchaseHistory, isFalse);
      expect(order.isTrackable, isFalse);
      expect(order.isSellerVisible, isFalse);
      expect(order.isFailedCheckout, isFalse);
      expect(orderStatusLabel(order.status), 'Awaiting payment');
    });

    test(
      'failed payment status is an unsuccessful checkout even if order is pending',
      () {
        final order = OrderModel.fromSupabase({
          'order_id': 'order-expired',
          'order_number': 'TL-4',
          'buyer_id': 'buyer-1',
          'seller_id': 'seller-1',
          'order_status': 'pending',
          'payments': [
            {'payment_status': 'failed'},
          ],
          'subtotal': 1000,
          'shipping_fee': 80,
          'platform_fee': 20,
          'total_amount': 1100,
          'created_at': '2026-09-12T02:00:00Z',
        });
        expect(order.isPaymentUnsuccessful, isTrue);
        expect(order.isFailedCheckout, isTrue);
        expect(order.needsBuyerPayment, isFalse);
        expect(order.showsInPurchaseHistory, isFalse);
      },
    );

    test('failed checkout is not a purchase and not a seller sale', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-voided',
        'order_number': 'TL-3',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'cancelled',
        'order_type': 'fixed_price',
        'subtotal': 1000,
        'shipping_fee': 80,
        'platform_fee': 20,
        'total_amount': 1100,
        'created_at': '2026-09-12T02:00:00Z',
      });
      expect(order.isFailedCheckout, isTrue);
      expect(order.isPaymentPending, isFalse);
      expect(order.needsBuyerPayment, isFalse);
      expect(order.showsInPurchaseHistory, isFalse);
      expect(order.isSellerVisible, isFalse);
      expect(order.isToShip, isFalse);
    });

    test('paid orders map to Paid / To ship and hide Pay Now', () {
      final order = OrderModel.fromSupabase({
        'order_id': 'order-paid',
        'order_number': 'TL-2',
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'order_status': 'paid',
        'subtotal': 1000,
        'shipping_fee': 80,
        'platform_fee': 20,
        'total_amount': 1100,
        'created_at': '2026-09-11T02:00:00Z',
      });
      expect(order.isPaymentPending, isFalse);
      expect(order.needsBuyerPayment, isFalse);
      expect(order.isFailedCheckout, isFalse);
      expect(order.isToShip, isTrue);
      expect(order.showsInPurchaseHistory, isTrue);
      expect(order.isSellerVisible, isTrue);
      expect(orderStatusLabel(order.status), 'Paid / To ship');
      expect(order.paymentMethod, PaymentMethod.paymongo);
    });
  });
}
