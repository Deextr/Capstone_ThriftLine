import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/confirmed_violation_labels.dart';
import 'package:thriftline/features/trust_safety/domain/confirmed_violation.dart';

void main() {
  group('ConfirmedViolationSummary', () {
    test('parses list RPC row', () {
      final item = ConfirmedViolationSummary.fromMap({
        'source': 'auction_bidding',
        'record_id': 'a1',
        'category': 'auction_bidding',
        'confirmed_at': '2026-11-01T10:00:00Z',
        'violation_number': 2,
        'consequence': 'bidding_restricted_3_days',
        'reference_title': 'Vintage bag',
        'penalty_status': 'restricted',
      });

      expect(item.source, 'auction_bidding');
      expect(item.recordId, 'a1');
      expect(item.violationNumber, 2);
      expect(item.referenceTitle, 'Vintage bag');
    });
  });

  group('confirmed violation filters', () {
    final lf = ConfirmedViolationSummary.fromMap({
      'source': 'looking_for',
      'record_id': '1',
      'category': 'looking_for',
      'confirmed_at': '2026-10-01T00:00:00Z',
      'penalty_status': 'recorded',
      'reference_title': 'Post',
    });
    final auction = ConfirmedViolationSummary.fromMap({
      'source': 'auction_bidding',
      'record_id': '2',
      'category': 'auction_bidding',
      'confirmed_at': '2026-10-15T00:00:00Z',
      'penalty_status': 'warning',
      'reference_title': 'Auction',
    });
    final report = ConfirmedViolationSummary.fromMap({
      'source': 'community_report',
      'record_id': '3',
      'category': 'failure_to_ship',
      'confirmed_at': '2026-11-01T00:00:00Z',
      'penalty_status': 'resolved',
      'reference_title': 'Order',
    });

    test('category filter excludes other sources', () {
      expect(
        matchesCategoryFilter(lf, ConfirmedViolationCategoryFilter.lookingFor),
        isTrue,
      );
      expect(
        matchesCategoryFilter(
          auction,
          ConfirmedViolationCategoryFilter.lookingFor,
        ),
        isFalse,
      );
      expect(
        matchesCategoryFilter(
          report,
          ConfirmedViolationCategoryFilter.communityReport,
        ),
        isTrue,
      );
    });

    test('penalty filter matches restriction and warnings', () {
      expect(
        matchesPenaltyFilter(
          'restricted',
          ConfirmedViolationPenaltyFilter.activeRestriction,
        ),
        isTrue,
      );
      expect(
        matchesPenaltyFilter(
          'warning',
          ConfirmedViolationPenaltyFilter.warningOnly,
        ),
        isTrue,
      );
      expect(
        matchesPenaltyFilter(
          'resolved',
          ConfirmedViolationPenaltyFilter.warningOnly,
        ),
        isFalse,
      );
    });

    test('date range filter uses UTC day boundaries', () {
      final confirmed = DateTime.utc(2026, 10, 10, 23, 59);
      expect(
        matchesConfirmedDateRange(
          confirmed,
          DateTime(2026, 10, 10),
          DateTime(2026, 10, 10),
        ),
        isTrue,
      );
      expect(
        matchesConfirmedDateRange(
          confirmed,
          DateTime(2026, 10, 11),
          null,
        ),
        isFalse,
      );
    });
  });

  group('labels', () {
    test('community categories use report reason labels', () {
      expect(
        confirmedViolationCategoryLabel('failure_to_ship'),
        isNotEmpty,
      );
    });

    test('penalty summary includes strike for Looking For', () {
      final item = ConfirmedViolationSummary.fromMap({
        'source': 'looking_for',
        'record_id': '1',
        'category': 'looking_for',
        'confirmed_at': '2026-10-01T00:00:00Z',
        'strike_number': 2,
        'penalty_status': 'restricted',
        'reference_title': 'Post',
      });
      expect(confirmedViolationPenaltySummary(item), contains('Strike 2'));
    });
  });
}
