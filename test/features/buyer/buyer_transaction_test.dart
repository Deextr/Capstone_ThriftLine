import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/buyer_transaction.dart';

void main() {
  group('buyer transaction mapping', () {
    test('maps paid to Successful and refunded to Refunded', () {
      expect(
        buyerTransactionStatusFromPayment('paid'),
        BuyerTransactionStatus.successful,
      );
      expect(
        buyerTransactionStatusFromPayment('refunded'),
        BuyerTransactionStatus.refunded,
      );
      expect(buyerTransactionStatusFromPayment('pending'), isNull);
      expect(buyerTransactionStatusFromPayment('failed'), isNull);
    });

    test('skips pending rows when parsing a payment list', () {
      final paid = BuyerTransaction.fromJson({
        'payment_id': 'p1',
        'order_id': 'o1',
        'order_number': 'TL-1',
        'product_title': 'Vintage jacket',
        'payment_status': 'paid',
        'amount_centavos': 18200,
        'paid_at': '2026-10-10T04:00:00.000Z',
        'payment_method': 'paymongo',
        'paymongo_channel': 'gcash',
      });
      expect(paid.status, BuyerTransactionStatus.successful);
      expect(paid.methodLabel, 'GCash');
      expect(
        () => BuyerTransaction.fromJson({
          'payment_id': 'p2',
          'payment_status': 'pending',
          'amount_centavos': 100,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('filter and sort visible transactions', () {
      final paid = BuyerTransaction.fromJson({
        'payment_id': 'p1',
        'order_id': 'o1',
        'order_number': 'TL-1',
        'product_title': 'A',
        'payment_status': 'paid',
        'amount_centavos': 100,
        'paid_at': '2026-10-10T04:00:00.000Z',
      });
      final refunded = BuyerTransaction.fromJson({
        'payment_id': 'p2',
        'order_id': 'o2',
        'order_number': 'TL-2',
        'product_title': 'B',
        'payment_status': 'refunded',
        'amount_centavos': 200,
        'paid_at': '2026-10-08T04:00:00.000Z',
        'refunded_at': '2026-10-12T04:00:00.000Z',
        'refund_amount_centavos': 200,
      });
      final all = [paid, refunded];
      expect(
        visibleBuyerTransactions(
          source: all,
          filter: BuyerTransactionFilter.refunded,
          sort: BuyerTransactionSort.newest,
        ).map((t) => t.paymentId),
        ['p2'],
      );
      expect(
        visibleBuyerTransactions(
          source: all,
          filter: BuyerTransactionFilter.all,
          sort: BuyerTransactionSort.oldest,
        ).map((t) => t.paymentId),
        ['p1', 'p2'],
      );
    });
  });
}
