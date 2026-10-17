import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/listing_shipping.dart';

void main() {
  test('free shipping mode preview is zero', () {
    final shipping = calculateShopFixedShippingPreview([
      const CartShippingLine(
        productId: 'p1',
        quantity: 1,
        mode: ListingShippingMode.free,
        shippingFee: 80,
      ),
    ]);
    expect(shipping, 0);
  });

  test('Buy Now preview uses listing shipping lines, not flat checkoutShippingFee(1)', () {
    final shipping = calculateShopFixedShippingPreview([
      const CartShippingLine(
        productId: 'p1',
        quantity: 1,
        mode: ListingShippingMode.fixedFee,
        shippingFee: 120,
      ),
    ]);
    expect(shipping, 120);
  });
}
