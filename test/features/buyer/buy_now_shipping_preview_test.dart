import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/listing_shipping.dart';

void main() {
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
