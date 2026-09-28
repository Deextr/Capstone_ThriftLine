import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/profile/data/buyer_address_validation.dart';
import 'package:thriftline/features/seller/domain/davao_barangay.dart';

void main() {
  final agdao = DavaoBarangay(
    code: '112402002',
    name: 'Agdao',
    cityCode: DavaoBarangay.cityCodePsgc9,
  );

  group('buyerAddressCity', () {
    test(
      'always persists Davao City even if the client sends another city',
      () {
        expect(buyerAddressCity(), DavaoBarangay.cityName);
        expect(buyerAddressCity('Manila'), DavaoBarangay.cityName);
        expect(buyerAddressCity(''), DavaoBarangay.cityName);
      },
    );
  });

  group('buyerAddressFormError', () {
    test('requires name, phone, street, and a loaded Davao barangay', () {
      expect(
        buyerAddressFormError(
          recipientName: '',
          phoneNumber: '09171234567',
          streetAddress: '123 Street',
          barangay: agdao,
          allowedBarangays: [agdao],
        ),
        'Name, phone, and street are required.',
      );
      expect(
        buyerAddressFormError(
          recipientName: 'Juan',
          phoneNumber: '09171234567',
          streetAddress: '123 Street',
          barangay: null,
          allowedBarangays: [agdao],
        ),
        'Please select a Davao City barangay.',
      );
      expect(
        buyerAddressFormError(
          recipientName: 'Juan',
          phoneNumber: '09171234567',
          streetAddress: '123 Street',
          barangay: agdao,
          allowedBarangays: [agdao],
        ),
        isNull,
      );
    });
  });
}
