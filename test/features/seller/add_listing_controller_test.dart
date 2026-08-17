// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/controllers/add_listing_controller.dart';
import 'package:thriftline/models/enums.dart';

// Feature: create-product-listing
// Property 7: condition mapping is bijective and complete
// Property 8: listing format mapping is bijective and complete

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Property 7 — Condition mapping is bijective and complete
  // Validates: Requirements 5.2
  // ─────────────────────────────────────────────────────────────────────────
  group('Property 7: conditionToDbString — bijective and complete', () {
    test('returns a non-empty string for every ProductCondition value', () {
      for (final condition in ProductCondition.values) {
        final result = conditionToDbString(condition);
        expect(
          result,
          isNotEmpty,
          reason: '$condition mapped to an empty string',
        );
      }
    });

    test('all results are distinct (no two enum values map to the same string)',
        () {
      final results =
          ProductCondition.values.map(conditionToDbString).toList();
      final uniqueResults = results.toSet();
      expect(
        uniqueResults.length,
        equals(results.length),
        reason:
            'Duplicate DB strings found: $results — mapping is not injective',
      );
    });

    test('maps to the exact expected DB values', () {
      expect(conditionToDbString(ProductCondition.newWithTags), equals('new'));
      expect(conditionToDbString(ProductCondition.likeNew), equals('like_new'));
      expect(conditionToDbString(ProductCondition.good), equals('good'));
      expect(conditionToDbString(ProductCondition.fair), equals('fair'));
    });

    test('covers all four ProductCondition cases', () {
      // Ensures the switch is exhaustive — the Dart compiler enforces this,
      // but this test makes the coverage requirement explicit.
      expect(ProductCondition.values, hasLength(4));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Property 8 — Listing format mapping is bijective and complete
  // Validates: Requirements 6.5
  // ─────────────────────────────────────────────────────────────────────────
  group('Property 8: formatToDbString — bijective and complete', () {
    test('returns a non-empty string for every ListingFormat value', () {
      for (final format in ListingFormat.values) {
        final result = formatToDbString(format);
        expect(
          result,
          isNotEmpty,
          reason: '$format mapped to an empty string',
        );
      }
    });

    test('all results are distinct (no two enum values map to the same string)',
        () {
      final results = ListingFormat.values.map(formatToDbString).toList();
      final uniqueResults = results.toSet();
      expect(
        uniqueResults.length,
        equals(results.length),
        reason:
            'Duplicate DB strings found: $results — mapping is not injective',
      );
    });

    test('maps to the exact expected DB values', () {
      expect(
          formatToDbString(ListingFormat.fixedPrice), equals('fixed_price'));
      expect(formatToDbString(ListingFormat.auction), equals('auction'));
      expect(
          formatToDbString(ListingFormat.liveSession), equals('live_session'));
    });

    test('covers all three ListingFormat cases', () {
      expect(ListingFormat.values, hasLength(3));
    });
  });
}
