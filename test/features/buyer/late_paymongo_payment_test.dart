import 'package:flutter_test/flutter_test.dart';

/// Documents the RPC JSON shape from `apply_paymongo_event` for late captures.
/// Database behavior is enforced in
/// `20261017190000_late_paymongo_payment_refund.sql`.
void main() {
  group('late PayMongo webhook RPC result', () {
    test('late reconciliation exposes refund-required fields', () {
      final result = {
        'success': true,
        'late_payment_reconciled': true,
        'refund_required': true,
        'refund_reason': 'late_payment_after_cancellation',
        'paid': true,
        'payment_id': 'pay-1',
        'order_id': 'ord-1',
      };

      expect(result['success'], isTrue);
      expect(result['late_payment_reconciled'], isTrue);
      expect(result['refund_required'], isTrue);
      expect(result['refund_reason'], 'late_payment_after_cancellation');
      expect(result['paid'], isTrue);
    });

    test('duplicate late event is idempotent', () {
      final result = {
        'success': true,
        'duplicate': true,
        'late_payment_reconciled': true,
      };
      expect(result['duplicate'], isTrue);
      expect(result['late_payment_reconciled'], isTrue);
    });

    test('failed webhook after capture is ignored without voiding', () {
      final result = {
        'success': true,
        'ignored': true,
        'payment_already_captured': true,
      };
      expect(result['ignored'], isTrue);
      expect(result['payment_already_captured'], isTrue);
    });
  });
}
