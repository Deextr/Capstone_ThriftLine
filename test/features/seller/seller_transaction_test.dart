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

    test('maps per-order commission, not per-product deductions', () {
      final sale = SellerTransaction.fromJson({
        'payment_id': 'p3',
        'order_id': 'o3',
        'order_number': 'TL-3',
        'product_title': 'Two items',
        'payment_status': 'paid',
        'amount_centavos': 76400,
        'seller_amount_centavos': 71500,
        'subtotal_centavos': 70000,
        'shipping_fee_centavos': 5000,
        'commission_rate': 0.05,
        'commission_amount_centavos': 3500,
        'commission_status': 'earned',
        'escrow_status': 'released',
      });
      expect(sale.commissionAmountCentavos, 3500);
      expect(sale.netProductEarningsCentavos, 66500);
      expect(sellerCommissionStatusLabel(sale.commissionStatus), 'Earned');
    });

    test('pending commission is labelled not yet earned', () {
      expect(sellerCommissionStatusLabel('pending'), 'Not yet earned');
    });

    test('commission reversed uses plain seller wording', () {
      final label = sellerCommissionStatusLabel('reversed');
      expect(label.toLowerCase(), isNot(contains('revers')));
      expect(label, 'Waived after refund');
    });

    test('seller status and refund hints avoid reversal terminology', () {
      final refunded = SellerTransaction.fromJson({
        'payment_id': 'p4',
        'order_id': 'o4',
        'order_number': 'TL-4',
        'product_title': 'Shirt',
        'payment_status': 'refunded',
        'amount_centavos': 1000,
        'seller_amount_centavos': 900,
        'refund_amount_centavos': 900,
        'refunded_at': '2026-10-12T04:00:00.000Z',
      });
      expect(
        sellerTransactionStatusLabel(refunded.status).toLowerCase(),
        isNot(contains('revers')),
      );
      final hint = sellerRefundEarningsListHint(refunded)!;
      expect(hint.toLowerCase(), isNot(contains('revers')));
      expect(hint, contains('returned to buyer'));
    });
  });
}
