import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/features/auth/data/shared_preferences_login_rate_limit_store.dart';
import 'package:thriftline/features/auth/domain/login_rate_limit_persistence.dart';
import 'package:thriftline/features/auth/domain/login_rate_limiter.dart';

class _MemoryLoginRateLimitPersistence implements LoginRateLimitPersistence {
  String? storedJson;

  @override
  Map<String, dynamic>? loadEntries() {
    if (storedJson == null) return null;
    final decoded = jsonDecode(storedJson!);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> saveEntries(Map<String, dynamic> entries) async {
    storedJson = jsonEncode(entries);
  }
}

LoginRateLimiter _newLimiter(_MemoryLoginRateLimitPersistence persistence) {
  return LoginRateLimiter(persistence);
}

void main() {
  const email = 'user@example.com';

  group('LoginRateLimiter', () {
    test('four failures do not lock out', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);

      for (var i = 0; i < 4; i++) {
        await limiter.recordFailure(email);
      }

      expect(limiter.isLockedOut(email), isFalse);
      expect(limiter.remainingLockout(email), Duration.zero);
    });

    test('five failures start a five-minute lockout', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);

      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure(email);
      }

      expect(limiter.isLockedOut(email), isTrue);
      expect(limiter.remainingLockout(email).inMinutes, greaterThanOrEqualTo(4));
      expect(limiter.lockoutMessageFor(email), isNotEmpty);
      expect(persistence.storedJson, isNotNull);
    });

    test('lockout survives a new limiter instance (app restart)', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final beforeRestart = _newLimiter(persistence);
      for (var i = 0; i < 5; i++) {
        await beforeRestart.recordFailure(email);
      }
      expect(beforeRestart.isLockedOut(email), isTrue);

      final afterRestart = _newLimiter(persistence);
      expect(afterRestart.isLockedOut(email), isTrue);
      expect(afterRestart.remainingLockout(email).inSeconds, greaterThan(0));
    });

    test('rapid failures persist the full attempt count', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);

      await Future.wait(
        List.generate(5, (_) => limiter.recordFailure(email)),
      );

      final restored = _newLimiter(persistence);
      expect(restored.failedAttempts(email), 5);
      expect(restored.isLockedOut(email), isTrue);
    });

    test('expired lockout is cleared and no longer blocks login', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);
      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure(email);
      }

      final entries = persistence.loadEntries()!;
      final key = LoginRateLimiter.normalizeEmailKey(email);
      final entry = Map<String, dynamic>.from(entries[key]! as Map);
      entry['lockoutUntilMs'] =
          DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch;
      entries[key] = entry;
      await persistence.saveEntries(entries);

      final restored = _newLimiter(persistence);
      expect(restored.isLockedOut(email), isFalse);
      expect(restored.failedAttempts(email), 5);
    });

    test('successful login clears persisted state for that email', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);
      await limiter.recordFailure(email);
      await limiter.recordFailure(email);
      await limiter.recordSuccess(email);

      expect(limiter.failedAttempts(email), 0);
      expect(persistence.loadEntries(), isEmpty);
    });

    test('rate limits are independent per email', () async {
      final persistence = _MemoryLoginRateLimitPersistence();
      final limiter = _newLimiter(persistence);

      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure(email);
      }
      expect(limiter.isLockedOut(email), isTrue);
      expect(limiter.isLockedOut('other@example.com'), isFalse);
    });

    test('normalizeEmailKey trims and lowercases', () {
      expect(
        LoginRateLimiter.normalizeEmailKey('  User@Example.COM '),
        'user@example.com',
      );
    });
  });

  group('SharedPreferences login rate limit store', () {
    test('persists lockout across new limiter instances', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      final store = SharedPreferencesLoginRateLimitStore(prefs);

      final first = LoginRateLimiter(store);
      for (var i = 0; i < 5; i++) {
        await first.recordFailure(email);
      }

      expect(
        prefs.getString(AppConstants.keyLoginRateLimitState),
        isNotNull,
      );

      final second = LoginRateLimiter(store);
      expect(second.isLockedOut(email), isTrue);
      expect(second.failedAttempts(email), 5);
    });
  });
}
