import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/shared_preferences_service.dart';
import '../domain/login_rate_limit_persistence.dart';

/// Stores login rate-limit entries in [SharedPreferencesService].
class SharedPreferencesLoginRateLimitStore
    implements LoginRateLimitPersistence {
  SharedPreferencesLoginRateLimitStore(this._prefs);

  final SharedPreferencesService _prefs;

  @override
  Map<String, dynamic>? loadEntries() {
    final raw = _prefs.getString(AppConstants.keyLoginRateLimitState);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveEntries(Map<String, dynamic> entries) async {
    await _prefs.setString(AppConstants.keyLoginRateLimitState, jsonEncode(entries));
  }
}
