import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/product_listing_validation.dart';

void main() {
  group('productDescriptionError', () {
    test('rejects empty description', () {
      expect(
        productDescriptionError(''),
        productDescriptionRequiredMessage,
      );
      expect(
        productDescriptionError('   '),
        productDescriptionRequiredMessage,
      );
    });

    test('rejects descriptions shorter than 20 characters', () {
      expect(
        productDescriptionError('a' * 15),
        productDescriptionTooShortMessage,
      );
      expect(
        productDescriptionError('a' * 19),
        productDescriptionTooShortMessage,
      );
    });

    test('accepts descriptions from 20 through 2000 characters', () {
      expect(productDescriptionError('a' * 20), isNull);
      expect(productDescriptionError('a' * 50), isNull);
      expect(productDescriptionError('a' * 150), isNull);
      expect(productDescriptionError('a' * 1999), isNull);
      expect(productDescriptionError('a' * 2000), isNull);
    });

    test('rejects descriptions longer than 2000 characters', () {
      expect(
        productDescriptionError('a' * 2001),
        productDescriptionTooLongMessage,
      );
    });
  });
}
