import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/buyer_transaction.dart';
import 'package:thriftline/features/seller/data/seller_earnings.dart';

void main() {
  group('BuyerTransaction.fromJson', () {
    test('reads refund_proof_available flag', () {
      final t = BuyerTransaction.fromJson({
        'payment_id': 'p1',
        'order_id': 'o1',
        'order_number': 'TL-1',
        'product_title': 'Item',
        'payment_status': 'refunded',
        'amount_centavos': 10000,
        'refund_state': 'manual_completed',
        'refund_proof_available': true,
      });
      expect(t.refundProofAvailable, isTrue);
    });
  });

  group('SellerPayoutRecord.fromMap', () {
    test('reads has_payout_proof flag', () {
      final p = SellerPayoutRecord.fromMap({
        'payout_id': 'pay-1',
        'amount_centavos': 50000,
        'status': 'paid',
        'has_payout_proof': true,
      });
      expect(p.payoutProofAvailable, isTrue);
    });
  });
}
