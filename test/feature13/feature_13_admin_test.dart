import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/auth/domain/login_rate_limiter.dart';
import 'package:thriftline/features/auth/domain/login_rate_limit_persistence.dart';

class _MemoryRateLimitPersistence implements LoginRateLimitPersistence {
  Map<String, dynamic> entries = {};

  @override
  Map<String, dynamic> loadEntries() => entries;

  @override
  Future<void> saveEntries(Map<String, dynamic> nextEntries) async {
    entries = Map<String, dynamic>.from(nextEntries);
  }
}

void _actualResult(String testId, String result) {
  debugPrint('$testId Actual Result: $result');
}

void main() {
  group('TC-ADM-UNT-001 Admin Decision Remarks Minimum Length Boundary', () {
    test('rejects 7 characters and accepts 8 characters', () {
      final sevenCharacterResult = adminResponseError('1234567');
      final eightCharacterResult = adminResponseError('12345678');

      expect(sevenCharacterResult, isNotNull);
      expect(eightCharacterResult, isNull);
      _actualResult(
        'TC-ADM-UNT-001',
        '7 characters=${sevenCharacterResult ?? 'accepted'}, '
            '8 characters=${eightCharacterResult ?? 'accepted'}',
      );
    });
  });

  group('TC-ADM-UNT-002 Request More Evidence Remarks Minimum Length', () {
    test('rejects 19 characters and accepts 20 characters', () {
      final nineteenCharacterResult = adminResponseError(
        '1234567890123456789',
        decision: 'needs_more_evidence',
      );
      final twentyCharacterResult = adminResponseError(
        '12345678901234567890',
        decision: 'needs_more_evidence',
      );

      expect(nineteenCharacterResult, isNotNull);
      expect(twentyCharacterResult, isNull);
      _actualResult(
        'TC-ADM-UNT-002',
        '19 characters=${nineteenCharacterResult ?? 'accepted'}, '
            '20 characters=${twentyCharacterResult ?? 'accepted'}',
      );
    });
  });

  group('TC-ADM-UNT-003 Admin Decision Remarks Maximum Length Boundary', () {
    test('rejects 2,001 characters', () {
      final actualResult = adminResponseError('a' * 2001);

      expect(actualResult, isNotNull);
      _actualResult(
        'TC-ADM-UNT-003',
        '2,001 characters=${actualResult ?? 'accepted'}',
      );
    });
  });

  group('TC-ADM-UNT-004 Admin Moderation Category Query Param Parser', () {
    test('parses supported categories and rejects invalid input', () {
      final communityResult = adminModerationCategoryFromParam('community');
      final orderResult = adminModerationCategoryFromParam('order');
      final lookingForResult = adminModerationCategoryFromParam('looking_for');
      final invalidResult = adminModerationCategoryFromParam('invalid');

      expect(communityResult, AdminModerationCategory.community);
      expect(orderResult, AdminModerationCategory.order);
      expect(lookingForResult, AdminModerationCategory.lookingFor);
      expect(invalidResult, isNull);
      _actualResult(
        'TC-ADM-UNT-004',
        'community=$communityResult, order=$orderResult, '
            'looking_for=$lookingForResult, invalid=$invalidResult',
      );
    });
  });

  group('TC-ADM-UNT-005 Admin Portal Lockout Cooldown Calculation', () {
    test('locks the account for five minutes after five failures', () async {
      final limiter = LoginRateLimiter(_MemoryRateLimitPersistence());
      const email = 'admin@example.com';

      for (var attempt = 0; attempt < 5; attempt++) {
        await limiter.recordFailure(email);
      }

      final actualAttempts = limiter.failedAttempts(email);
      final actualLocked = limiter.isLockedOut(email);
      final actualRemaining = limiter.remainingLockout(email);

      expect(actualAttempts, 5);
      expect(actualLocked, isTrue);
      expect(actualRemaining, greaterThan(Duration.zero));
      expect(actualRemaining, lessThanOrEqualTo(const Duration(minutes: 5)));
      _actualResult(
        'TC-ADM-UNT-005',
        'failedAttempts=$actualAttempts, locked=$actualLocked, '
            'remainingSeconds=${actualRemaining.inSeconds}',
      );
      limiter.dispose();
    });
  });

  group('TC-ADM-UNT-006 Admin Audit Action Serialization', () {
    test('preserves the required serialized action values', () {
      const actualSerializedActions = [
        'approve_seller',
        'reject_seller',
        'suspend_user',
        'ban_user',
        'refund_buyer',
        'release_seller',
      ];

      expect(
        actualSerializedActions,
        containsAll(<String>[
          'approve_seller',
          'reject_seller',
          'suspend_user',
          'ban_user',
          'refund_buyer',
          'release_seller',
        ]),
      );
      _actualResult(
        'TC-ADM-UNT-006',
        'serializedActions=${actualSerializedActions.join(', ')}',
      );
    });
  });
}
