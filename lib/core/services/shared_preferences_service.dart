import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Wrapper around [SharedPreferences] for typed, key-safe persistence.
class SharedPreferencesService {
  SharedPreferencesService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesService(prefs);
  }

  // Onboarding
  bool get isOnboardingComplete =>
      _prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;

  Future<bool> setOnboardingComplete(bool value) =>
      _prefs.setBool(AppConstants.keyOnboardingComplete, value);

  // Auth
  bool get isLoggedIn => _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  Future<bool> setLoggedIn(bool value) =>
      _prefs.setBool(AppConstants.keyIsLoggedIn, value);

  // Theme
  String? get themeMode => _prefs.getString(AppConstants.keyThemeMode);

  Future<bool> setThemeMode(String value) =>
      _prefs.setString(AppConstants.keyThemeMode, value);

  // User role
  String? get userRole => _prefs.getString(AppConstants.keyUserRole);

  Future<bool> setUserRole(String value) =>
      _prefs.setString(AppConstants.keyUserRole, value);

  // Auth session
  String? get username => _prefs.getString(AppConstants.keyUsername);

  Future<bool> setUsername(String value) =>
      _prefs.setString(AppConstants.keyUsername, value);

  String? get userId => _prefs.getString(AppConstants.keyUserId);

  Future<bool> setUserId(String value) =>
      _prefs.setString(AppConstants.keyUserId, value);

  String? get displayName => _prefs.getString(AppConstants.keyDisplayName);

  Future<bool> setDisplayName(String value) =>
      _prefs.setString(AppConstants.keyDisplayName, value);

  bool get isEmailOtpPending =>
      _prefs.getBool(AppConstants.keyEmailOtpPending) ?? false;

  Future<bool> setEmailOtpPending(bool value) =>
      _prefs.setBool(AppConstants.keyEmailOtpPending, value);

  /// Last Buyer/Seller workspace for [userId] on this device.
  ///
  /// Kept across logout so the same person returns to the mode they left.
  /// A different user on this device does not inherit the previous mode.
  String? activeAccountFor(String userId) {
    final storedUserId = _prefs.getString(AppConstants.keyActiveAccountUserId);
    if (storedUserId != userId) return null;
    return _prefs.getString(AppConstants.keyActiveAccount);
  }

  Future<void> setActiveAccount({
    required String userId,
    required String mode,
  }) async {
    await _prefs.setString(AppConstants.keyActiveAccountUserId, userId);
    await _prefs.setString(AppConstants.keyActiveAccount, mode);
  }

  List<String> recentSearchesFor(String userId) {
    return _prefs.getStringList(
          '${AppConstants.keyRecentSearchesPrefix}$userId',
        ) ??
        const [];
  }

  Future<void> setRecentSearches(String userId, List<String> queries) {
    return _prefs.setStringList(
      '${AppConstants.keyRecentSearchesPrefix}$userId',
      queries,
    );
  }

  Future<void> clearAuthSession() async {
    await setLoggedIn(false);
    await remove(AppConstants.keyUserRole);
    await remove(AppConstants.keyUsername);
    await remove(AppConstants.keyUserId);
    await remove(AppConstants.keyDisplayName);
    await remove(AppConstants.keyEmailOtpPending);
  }

  // Generic helpers
  Future<bool> remove(String key) => _prefs.remove(key);

  Future<bool> clear() => _prefs.clear();
}
