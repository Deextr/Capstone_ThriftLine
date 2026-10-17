import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/seller_address_draft.dart';

void main() {
  group('sellerShopNameError', () {
    test('rejects empty shop name', () {
      expect(sellerShopNameError(''), sellerShopNameRequiredMessage);
      expect(sellerShopNameError('   '), sellerShopNameRequiredMessage);
    });

    test('rejects one- and two-character shop names', () {
      expect(sellerShopNameError('A'), sellerShopNameTooShortMessage);
      expect(sellerShopNameError('AB'), sellerShopNameTooShortMessage);
    });

    test('accepts valid shop names', () {
      expect(sellerShopNameError('ABC'), isNull);
      expect(sellerShopNameError('Davao Vintage Vault'), isNull);
    });

    test('rejects shop names longer than 80 characters', () {
      expect(sellerShopNameError('a' * 81), sellerShopNameTooLongMessage);
      expect(sellerShopNameError('a' * 80), isNull);
    });
  });

  group('sellerShopAddressLine1Error', () {
    test('rejects empty address', () {
      expect(sellerShopAddressLine1Error(''), sellerShopAddressRequiredMessage);
      expect(
        sellerShopAddressLine1Error('   '),
        sellerShopAddressRequiredMessage,
      );
    });

    test('rejects one- and two-character addresses', () {
      expect(
        sellerShopAddressLine1Error('A'),
        sellerShopAddressTooShortMessage,
      );
      expect(
        sellerShopAddressLine1Error('AB'),
        sellerShopAddressTooShortMessage,
      );
    });

    test('accepts valid addresses', () {
      expect(sellerShopAddressLine1Error('ABC'), isNull);
      expect(
        sellerShopAddressLine1Error('123 Mango Ave, Barangay 9-A'),
        isNull,
      );
    });
  });
}
