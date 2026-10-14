import 'dart:async';

import 'package:flutter/foundation.dart';

import 'login_rate_limit_persistence.dart';

/// Incremental login rate limiter that tracks failed attempts and enforces
/// escalating lockout durations. State is persisted per normalized email.
///
/// Lockout schedule:
/// - 5 failed attempts  → 5-minute lockout
/// - 10 failed attempts → 10-minute lockout
/// - 15+ failed attempts → 30-minute lockout
///
/// The counter resets after a successful login or after the lockout expires
/// without new failures.
class LoginRateLimiter extends ChangeNotifier {
  LoginRateLimiter(this._persistence) {
    _entries = _decodeAllEntries(_persistence.loadEntries());
    _pruneExpiredLockouts();
  }

  final LoginRateLimitPersistence _persistence;

  /// Authoritative in-memory copy; disk is updated after each mutation.
  late Map<String, dynamic> _entries;

  String _displayEmail = '';
  Timer? _lockoutTimer;
  Future<void>? _persistChain;

  /// Normalizes email for use as a storage key (trim + lowercase).
  @visibleForTesting
  static String normalizeEmailKey(String email) => email.trim().toLowerCase();

  /// Email currently shown on the login form (drives countdown UI).
  void setDisplayEmail(String email) {
    _displayEmail = normalizeEmailKey(email);
    _syncLockoutTimer();
    notifyListeners();
  }

  /// Number of consecutive failed login attempts for [email].
  int failedAttempts(String email) {
    return _readEntry(email)?.failedAttempts ?? 0;
  }

  /// Whether [email] is currently locked out.
  bool isLockedOut(String email) {
    final entry = _readEntry(email);
    if (entry == null || entry.lockoutUntil == null) return false;
    if (DateTime.now().isAfter(entry.lockoutUntil!)) {
      _clearExpiredLockout(email, entry);
      return false;
    }
    return true;
  }

  /// Remaining lockout duration for [email]. Returns [Duration.zero] if not locked out.
  Duration remainingLockout(String email) {
    final entry = _readEntry(email);
    if (entry?.lockoutUntil == null) return Duration.zero;
    final remaining = entry!.lockoutUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Human-readable string for the remaining lockout time on the display email.
  String get lockoutMessage => lockoutMessageFor(_displayEmail);

  /// Human-readable lockout countdown for [email].
  String lockoutMessageFor(String email) {
    final rem = remainingLockout(email);
    if (rem == Duration.zero) return '';
    final mins = rem.inMinutes;
    final secs = rem.inSeconds % 60;
    if (mins > 0) {
      return 'Too many failed attempts. Try again in '
          '${mins}m ${secs.toString().padLeft(2, '0')}s.';
    }
    return 'Too many failed attempts. Try again in ${secs}s.';
  }

  /// Records a failed login attempt and starts a lockout if a threshold is hit.
  Future<void> recordFailure(String email) async {
    final key = normalizeEmailKey(email);
    if (key.isEmpty) return;

    final entry = _readEntry(email) ?? _LoginRateLimitEntry(failedAttempts: 0);
    final attempts = entry.failedAttempts + 1;
    var lockoutUntil = entry.lockoutUntil;
    final lockoutDuration = _lockoutDurationForAttempt(attempts);
    if (lockoutDuration != null) {
      lockoutUntil = DateTime.now().add(lockoutDuration);
    }

    _writeEntry(
      key,
      _LoginRateLimitEntry(
        failedAttempts: attempts,
        lockoutUntil: lockoutUntil,
      ),
    );
    await _flushPersist();
    _syncLockoutTimer();
    notifyListeners();
  }

  /// Resets all state for [email] after a successful login.
  Future<void> recordSuccess(String email) async {
    final key = normalizeEmailKey(email);
    if (key.isEmpty) return;

    _entries.remove(key);
    await _flushPersist();
    _syncLockoutTimer();
    notifyListeners();
  }

  Duration? _lockoutDurationForAttempt(int attempt) {
    if (attempt == 5) return const Duration(minutes: 5);
    if (attempt == 10) return const Duration(minutes: 10);
    if (attempt >= 15 && (attempt - 15) % 5 == 0) {
      return const Duration(minutes: 30);
    }
    return null;
  }

  void _pruneExpiredLockouts() {
    final now = DateTime.now();
    var changed = false;
    for (final key in _entries.keys.toList()) {
      final entry = _entryFromStored(_entries[key]);
      if (entry == null) {
        _entries.remove(key);
        changed = true;
        continue;
      }
      if (entry.lockoutUntil != null && now.isAfter(entry.lockoutUntil!)) {
        _entries[key] = _LoginRateLimitEntry(
          failedAttempts: entry.failedAttempts,
          lockoutUntil: null,
        ).toJson();
        changed = true;
      }
    }
    if (changed) {
      unawaited(_flushPersist());
    }
  }

  void _clearExpiredLockout(String email, _LoginRateLimitEntry entry) {
    final key = normalizeEmailKey(email);
    _writeEntry(
      key,
      _LoginRateLimitEntry(
        failedAttempts: entry.failedAttempts,
        lockoutUntil: null,
      ),
    );
    unawaited(_flushPersist());
  }

  _LoginRateLimitEntry? _readEntry(String email) {
    final key = normalizeEmailKey(email);
    if (key.isEmpty) return null;
    return _entryFromStored(_entries[key]);
  }

  void _writeEntry(String key, _LoginRateLimitEntry entry) {
    _entries[key] = entry.toJson();
  }

  static Map<String, dynamic> _decodeAllEntries(Map<String, dynamic>? loaded) {
    if (loaded == null || loaded.isEmpty) return {};
    return Map<String, dynamic>.from(loaded);
  }

  static _LoginRateLimitEntry? _entryFromStored(Object? raw) {
    if (raw is! Map) return null;
    return _LoginRateLimitEntry.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> _flushPersist() async {
    final snapshot = Map<String, dynamic>.from(_entries);
    final previous = _persistChain ?? Future<void>.value();
    _persistChain = previous.then((_) async {
      try {
        await _persistence.saveEntries(snapshot);
      } catch (e, st) {
        debugPrint('LoginRateLimiter: failed to persist rate-limit state: $e');
        debugPrint('$st');
      }
    });
    await _persistChain;
  }

  void _syncLockoutTimer() {
    final shouldRun = _displayEmail.isNotEmpty && isLockedOut(_displayEmail);
    if (!shouldRun) {
      _lockoutTimer?.cancel();
      _lockoutTimer = null;
      return;
    }
    if (_lockoutTimer != null) return;

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_displayEmail.isEmpty || !isLockedOut(_displayEmail)) {
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }
}

class _LoginRateLimitEntry {
  _LoginRateLimitEntry({required this.failedAttempts, this.lockoutUntil});

  final int failedAttempts;
  final DateTime? lockoutUntil;

  factory _LoginRateLimitEntry.fromJson(Map<String, dynamic> json) {
    final lockoutMs = json['lockoutUntilMs'];
    return _LoginRateLimitEntry(
      failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
      lockoutUntil: lockoutMs is num
          ? DateTime.fromMillisecondsSinceEpoch(lockoutMs.toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'failedAttempts': failedAttempts,
    if (lockoutUntil != null)
      'lockoutUntilMs': lockoutUntil!.millisecondsSinceEpoch,
  };
}
