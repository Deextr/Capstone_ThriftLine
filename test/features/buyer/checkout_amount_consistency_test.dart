import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_totals.dart';

void main() {
  group('checkout amount consistency', () {
    test('2% platform fee on 15.00 subtotal yields 15.30 total with no shipping', () {
      const subtotal = 15.0;
      const shipping = 0.0;
      final platform = checkoutPlatformFee(subtotal);
      final total = checkoutTotal(
        subtotal: subtotal,
        shippingFee: shipping,
        platformFee: platform,
      );
      expect(platform, 0.30);
      expect(total, 15.30);
      expect((total * 100).round(), 1530);
    });

    test('platform fee is not double-applied in total', () {
      const subtotal = 100.0;
      final platform = checkoutPlatformFee(subtotal);
      final total = checkoutTotal(
        subtotal: subtotal,
        shippingFee: 80,
        platformFee: platform,
      );
      expect(total, subtotal + 80 + platform);
      expect(platform, 2.0);
    });
  });
}
