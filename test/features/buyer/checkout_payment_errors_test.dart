import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_payment_errors.dart';

void main() {
  group('buyerFacingPaymentStartError', () {
    test('never exposes seller listing limit text', () {
      const raw =
          'listing_limit_reached: You can have up to 10 active listings at a time.';
      final message = buyerFacingPaymentStartError(raw);
      expect(message.contains('10 active listings'), isFalse);
      expect(message.contains('listing_limit'), isFalse);
    });

    test('maps void_unpaid_checkout ambiguity to retry copy', () {
      final message = buyerFacingPaymentStartError(
        'function public.void_unpaid_checkout(uuid) is not unique',
      );
      expect(
        message,
        'We could not prepare your payment. Please try again in a moment.',
      );
    });
  });
}
