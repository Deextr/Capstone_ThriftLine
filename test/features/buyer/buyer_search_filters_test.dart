import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/models/buyer_search_filters.dart';

void main() {
  group('BuyerSearchFilters.isPriceRangeValid', () {
    test('rejects min greater than max', () {
      const filters = BuyerSearchFilters(minPrice: 500, maxPrice: 200);
      expect(filters.isPriceRangeValid, isFalse);
    });

    test('accepts equal min and max', () {
      const filters = BuyerSearchFilters(minPrice: 200, maxPrice: 200);
      expect(filters.isPriceRangeValid, isTrue);
    });

    test('accepts min less than max', () {
      const filters = BuyerSearchFilters(minPrice: 100, maxPrice: 500);
      expect(filters.isPriceRangeValid, isTrue);
    });

    test('accepts optional single-sided bounds', () {
      expect(const BuyerSearchFilters(minPrice: 100).isPriceRangeValid, isTrue);
      expect(const BuyerSearchFilters(maxPrice: 500).isPriceRangeValid, isTrue);
      expect(BuyerSearchFilters.cleared.isPriceRangeValid, isTrue);
    });
  });
}
