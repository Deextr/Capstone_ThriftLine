/// Persists per-email login rate-limit state across app restarts.
abstract interface class LoginRateLimitPersistence {
  /// Map of normalized email → entry map (`failedAttempts`, `lockoutUntilMs`).
  Map<String, dynamic>? loadEntries();

  Future<void> saveEntries(Map<String, dynamic> entries);
}
