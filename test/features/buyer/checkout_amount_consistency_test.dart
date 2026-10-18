import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_totals.dart';

void main() {
  group('checkout amount consistency', () {
    test(
      '2% platform fee on 15.00 subtotal yields 15.30 total with no shipping',
      () {
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
      },
    );

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

  group('seller order commission (5% of product subtotal)', () {
    test('one product uses 5% of that subtotal', () {
      expect(sellerOrderCommission(400), 20);
      expect(sellerNetProductEarnings(400), 380);
      expect(sellerTotalEarnings(productSubtotal: 400, shippingFee: 50), 430);
    });

    test('two products share one commission on the combined subtotal', () {
      expect(sellerOrderCommission(700), 35);
      expect(sellerNetProductEarnings(700), 665);
      expect(sellerTotalEarnings(productSubtotal: 700, shippingFee: 50), 715);
    });

    test('shipping is excluded from the commission base', () {
      expect(sellerOrderCommission(500), 25);
      expect(sellerTotalEarnings(productSubtotal: 500, shippingFee: 80), 555);
      expect(sellerTotalEarnings(productSubtotal: 500, shippingFee: 0), 475);
    });

    test('multi-shop checkouts keep independent per-order commissions', () {
      expect(sellerOrderCommission(700) + sellerOrderCommission(400), 55);
    });

    test('buyer PayMongo fee stays a separate 2% of subtotal', () {
      expect(checkoutPlatformFee(700), 14);
      expect(sellerOrderCommission(700), 35);
      expect(checkoutPlatformFee(700), isNot(sellerOrderCommission(700)));
    });
  });
}
