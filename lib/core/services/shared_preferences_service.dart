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

  Future<void> clearAuthSession() async {
    await setLoggedIn(false);
    await remove(AppConstants.keyUserRole);
    await remove(AppConstants.keyUsername);
    await remove(AppConstants.keyUserId);
    await remove(AppConstants.keyDisplayName);
  }

  // Generic helpers
  Future<bool> remove(String key) => _prefs.remove(key);

  Future<bool> clear() => _prefs.clear();
}
