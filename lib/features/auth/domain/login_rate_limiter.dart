import 'dart:async';

import 'package:flutter/foundation.dart';

/// Incremental login rate limiter that tracks failed attempts and enforces
/// escalating lockout durations.
///
/// Lockout schedule:
/// - 5 failed attempts  → 5-minute lockout
/// - 10 failed attempts → 10-minute lockout
/// - 15+ failed attempts → 30-minute lockout
///
/// The counter resets after a successful login or after the lockout expires
/// without new failures.
class LoginRateLimiter extends ChangeNotifier {
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;

  /// Number of consecutive failed login attempts.
  int get failedAttempts => _failedAttempts;

  /// Whether the user is currently locked out.
  bool get isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      // Lockout expired naturally — don't reset the counter so the next
      // tier still applies if they keep failing.
      _lockoutUntil = null;
      _lockoutTimer?.cancel();
      _lockoutTimer = null;
      return false;
    }
    return true;
  }

  /// Remaining lockout duration. Returns [Duration.zero] if not locked out.
  Duration get remainingLockout {
    if (_lockoutUntil == null) return Duration.zero;
    final remaining = _lockoutUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Human-readable string for the remaining lockout time.
  String get lockoutMessage {
    final rem = remainingLockout;
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
  void recordFailure() {
    _failedAttempts++;
    final lockoutDuration = _lockoutDurationForAttempt(_failedAttempts);
    if (lockoutDuration != null) {
      _startLockout(lockoutDuration);
    }
    notifyListeners();
  }

  /// Resets all state after a successful login.
  void recordSuccess() {
    _failedAttempts = 0;
    _lockoutUntil = null;
    _lockoutTimer?.cancel();
    _lockoutTimer = null;
    notifyListeners();
  }

  /// Returns the lockout duration when a threshold is exactly hit, or `null`
  /// if no new lockout should start at this attempt count.
  Duration? _lockoutDurationForAttempt(int attempt) {
    if (attempt == 5) return const Duration(minutes: 5);
    if (attempt == 10) return const Duration(minutes: 10);
    if (attempt >= 15 && (attempt - 15) % 5 == 0) {
      return const Duration(minutes: 30);
    }
    return null;
  }

  void _startLockout(Duration duration) {
    _lockoutUntil = DateTime.now().add(duration);
    _lockoutTimer?.cancel();
    // Tick every second so the countdown UI updates.
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isLockedOut) {
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
