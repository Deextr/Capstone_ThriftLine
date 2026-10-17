import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/buyer_transaction.dart';
import 'package:thriftline/features/seller/data/seller_transaction.dart';

void main() {
  group('seller transaction mapping', () {
    test('parses paid sale with seller earnings', () {
      final sale = SellerTransaction.fromJson({
        'payment_id': 'p1',
        'order_id': 'o1',
        'order_number': 'TL-1',
        'product_title': 'Vintage jacket',
        'payment_status': 'paid',
        'amount_centavos': 20000,
        'seller_amount_centavos': 17000,
        'paid_at': '2026-10-10T04:00:00.000Z',
        'escrow_status': 'released',
        'payment_method': 'paymongo',
        'paymongo_channel': 'qrph',
      });
      expect(sale.status, BuyerTransactionStatus.successful);
      expect(sale.sellerAmountCentavos, 17000);
      expect(sale.buyerPaidCentavos, 20000);
      expect(sale.methodLabel, 'QR Ph');
      expect(
        sellerTransactionEarningsLabel(sale.escrowStatus),
        'Paid out to balance',
      );
    });

    test('filter and sort visible seller transactions', () {
      final paid = SellerTransaction.fromJson({
        'payment_id': 'p1',
        'order_id': 'o1',
        'order_number': 'TL-1',
        'product_title': 'A',
        'payment_status': 'paid',
        'amount_centavos': 100,
        'seller_amount_centavos': 85,
        'paid_at': '2026-10-10T04:00:00.000Z',
      });
      final refunded = SellerTransaction.fromJson({
        'payment_id': 'p2',
        'order_id': 'o2',
        'order_number': 'TL-2',
        'product_title': 'B',
        'payment_status': 'refunded',
        'amount_centavos': 200,
        'seller_amount_centavos': 170,
        'paid_at': '2026-10-08T04:00:00.000Z',
        'refunded_at': '2026-10-12T04:00:00.000Z',
        'refund_amount_centavos': 170,
        'escrow_status': 'refunded',
      });
      final all = [paid, refunded];
      expect(
        visibleSellerTransactions(
          source: all,
          filter: BuyerTransactionFilter.refunded,
          sort: BuyerTransactionSort.newest,
        ).map((t) => t.paymentId),
        ['p2'],
      );
      expect(
        visibleSellerTransactions(
          source: all,
          filter: BuyerTransactionFilter.all,
          sort: BuyerTransactionSort.oldest,
        ).map((t) => t.paymentId),
        ['p1', 'p2'],
      );
    });
  });
}
