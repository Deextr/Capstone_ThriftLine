import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/checkout_address_validation.dart';
import 'package:thriftline/models/address_model.dart';

void main() {
  test('requires a complete address and 09 mobile before paying', () {
    expect(checkoutDeliveryAddressError(null), isNotNull);
    expect(
      checkoutDeliveryAddressError(
        const AddressModel(
          id: 'a1',
          userId: 'u1',
          recipientName: 'Buyer',
          phoneNumber: '09171234567',
          streetAddress: '123 Main',
          barangay: 'Buhangin',
          city: 'Davao City',
          isDefault: true,
        ),
      ),
      isNull,
    );
    expect(
      checkoutDeliveryAddressError(
        const AddressModel(
          id: 'a2',
          userId: 'u1',
          recipientName: 'Buyer',
          phoneNumber: '8171234567',
          streetAddress: '123 Main',
          barangay: 'Buhangin',
          city: 'Davao City',
          isDefault: true,
        ),
      ),
      contains('09'),
    );
  });
}
