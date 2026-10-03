import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_shop_address.dart';
import 'package:thriftline/features/seller/domain/seller_address_draft.dart';

void main() {
  test('parseStoredShopAddress splits line 2', () {
    final parsed = SellerAddressDraft.parseStoredShopAddress(
      '123 Main St, Unit 4B',
    );
    expect(parsed.line1, '123 Main St');
    expect(parsed.line2, 'Unit 4B');
  });

  test('fromProfileRow maps seller_profiles columns', () {
    final model = SellerShopAddress.fromProfileRow({
      'shop_name': 'Vintage Hub',
      'shop_address': '123 Main St, Unit 4B',
      'barangay': 'Buhangin',
      'city': 'Davao City',
    });
    expect(model.shopName, 'Vintage Hub');
    expect(model.barangayName, 'Buhangin');
    expect(model.addressLine1, '123 Main St');
    expect(model.addressLine2, 'Unit 4B');
  });
}
