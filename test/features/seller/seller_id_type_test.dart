import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/seller_id_type.dart';

void main() {
  group('SellerIdType', () {
    test('exposes only the six allowed labels', () {
      expect(
        SellerIdType.values.map((type) => type.label).toList(),
        [
          'National ID',
          "Driver's License",
          'Passport',
          'SSS ID',
          'UMID ID',
          'Student ID',
        ],
      );
    });

    test('does not include Voter\'s ID or PhilHealth ID', () {
      final labels = SellerIdType.values.map((type) => type.label.toLowerCase());
      expect(labels.any((label) => label.contains('voter')), isFalse);
      expect(labels.any((label) => label.contains('philhealth')), isFalse);
    });

    test('parses allowed storage values', () {
      expect(SellerIdType.tryParse('national_id'), SellerIdType.nationalId);
      expect(SellerIdType.tryParse('Driver\'s License'), isNull);
      expect(SellerIdType.tryParse('sss_id'), SellerIdType.sssId);
    });

    test('does not treat unspecified storage as a user-selected type', () {
      expect(SellerIdType.tryParse(SellerIdType.unspecifiedStorageValue), isNull);
    });

    test('rejects prohibited and unknown types', () {
      expect(SellerIdType.tryParse('voters_id'), isNull);
      expect(SellerIdType.tryParse('voter_id'), isNull);
      expect(SellerIdType.tryParse('philhealth_id'), isNull);
      expect(SellerIdType.tryParse('philhealth'), isNull);
      expect(SellerIdType.tryParse('government_id'), isNull);
      expect(SellerIdType.tryParse(null), isNull);
    });
  });
}
