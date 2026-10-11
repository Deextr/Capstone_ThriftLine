import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/domain/auction_bidding_violations.dart';

void main() {
  group('formatOrdinalViolationCount', () {
    test('formats first through third', () {
      expect(formatOrdinalViolationCount(1), '1st violation');
      expect(formatOrdinalViolationCount(2), '2nd violation');
      expect(formatOrdinalViolationCount(3), '3rd violation');
    });

    test('formats counts beyond threshold', () {
      expect(formatOrdinalViolationCount(4), '4th violation');
      expect(formatOrdinalViolationCount(11), '11th violation');
    });
  });

  group('violationStageLabel', () {
    test('reflects enforcement threshold', () {
      expect(violationStageLabel(1), 'First Violation');
      expect(violationStageLabel(2), 'Second Violation');
      expect(violationStageLabel(3), 'Penalty Threshold Reached');
      expect(violationStageLabel(5), 'Penalty Threshold Reached');
    });
  });

  group('resolveBiddingEnforcementStatus', () {
    test('restricted when window active', () {
      final now = DateTime(2026, 10, 10, 12);
      expect(
        resolveBiddingEnforcementStatus(
          permanentlyDisabledAt: null,
          restrictedUntil: now.add(const Duration(hours: 1)),
          accountStatus: 'active',
          now: now,
        ),
        BiddingEnforcementStatus.restricted,
      );
    });

    test('banned when permanently disabled', () {
      expect(
        resolveBiddingEnforcementStatus(
          permanentlyDisabledAt: DateTime(2026, 10, 1),
          restrictedUntil: null,
          accountStatus: 'active',
        ),
        BiddingEnforcementStatus.banned,
      );
    });

    test('active again after restriction expires', () {
      final now = DateTime(2026, 10, 10, 12);
      expect(
        resolveBiddingEnforcementStatus(
          permanentlyDisabledAt: null,
          restrictedUntil: now.subtract(const Duration(minutes: 1)),
          accountStatus: 'active',
          now: now,
        ),
        BiddingEnforcementStatus.active,
      );
    });
  });

  group('formatBiddingRestrictionRemaining', () {
    test('uses days when more than one day left', () {
      final now = DateTime(2026, 10, 10, 12);
      expect(
        formatBiddingRestrictionRemaining(
          now.add(const Duration(days: 2, hours: 3)),
          now: now,
        ),
        '2 days remaining',
      );
    });

    test('uses hours and minutes when one day or less', () {
      final now = DateTime(2026, 10, 10, 12);
      expect(
        formatBiddingRestrictionRemaining(
          now.add(const Duration(hours: 16, minutes: 30)),
          now: now,
        ),
        '16 hours and 30 minutes remaining',
      );
    });
  });

  group('filters', () {
    test('violation count filter', () {
      expect(
        matchesViolationCountFilter(1, ViolationCountFilter.first),
        isTrue,
      );
      expect(
        matchesViolationCountFilter(2, ViolationCountFilter.first),
        isFalse,
      );
      expect(
        matchesViolationCountFilter(3, ViolationCountFilter.threeOnly),
        isTrue,
      );
      expect(
        matchesViolationCountFilter(4, ViolationCountFilter.threeOnly),
        isFalse,
      );
    });

    test('buyer search', () {
      expect(
        matchesBuyerSearch(
          query: 'jane@',
          displayName: 'Jane',
          email: 'jane@example.com',
          username: 'jdoe',
          userId: 'uuid',
        ),
        isTrue,
      );
    });
  });
}
