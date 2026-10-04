import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/providers/theme_provider.dart';

import '../support/qa_reporter.dart';

Future<SharedPreferencesService> _prefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferencesService.init();
}

void providersUnitTests() {
  qaGroup('SharedPreferencesService', () {
    qaUnitTest('defaults are false/null on a fresh install', () async {
      final prefs = await _prefs();
      expect(prefs.isOnboardingComplete, isFalse);
      expect(prefs.isLoggedIn, isFalse);
      expect(prefs.themeMode, isNull);
      expect(prefs.userId, isNull);
    });

    qaUnitTest('active account is scoped to the same user', () async {
      final prefs = await _prefs();
      await prefs.setActiveAccount(userId: 'user-1', mode: 'seller');

      expect(prefs.activeAccountFor('user-1'), 'seller');
      expect(prefs.activeAccountFor('user-2'), isNull);
    });

    qaUnitTest('recent searches are stored per user', () async {
      final prefs = await _prefs();
      expect(prefs.recentSearchesFor('user-1'), isEmpty);

      await prefs.setRecentSearches('user-1', ['denim', 'y2k']);
      expect(prefs.recentSearchesFor('user-1'), ['denim', 'y2k']);
      expect(prefs.recentSearchesFor('user-2'), isEmpty);
    });

    qaUnitTest('clearAuthSession keeps the device trust marker', () async {
      final prefs = await _prefs({
        AppConstants.keyIsLoggedIn: true,
        AppConstants.keyUserId: 'user-1',
        AppConstants.keyUserRole: 'buyer',
        AppConstants.keyDisplayName: 'Dexter',
        AppConstants.keyDeviceTrustInstall: 'install-123',
      });

      await prefs.clearAuthSession();

      expect(prefs.isLoggedIn, isFalse);
      expect(prefs.userId, isNull);
      expect(prefs.userRole, isNull);
      expect(prefs.displayName, isNull);
      expect(prefs.deviceTrustInstallId, 'install-123');
    });
  });

  qaGroup('ThemeProvider', () {
    qaUnitTest('defaults to the system theme', () async {
      final provider = ThemeProvider(await _prefs());
      expect(provider.themeMode, ThemeMode.system);
      expect(provider.isDarkMode, isFalse);
    });

    qaUnitTest('restores a stored theme', () async {
      final provider = ThemeProvider(
        await _prefs({AppConstants.keyThemeMode: 'dark'}),
      );
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, isTrue);
    });

    qaUnitTest('ignores an invalid stored theme', () async {
      final provider = ThemeProvider(
        await _prefs({AppConstants.keyThemeMode: 'purple'}),
      );
      expect(provider.themeMode, ThemeMode.system);
    });

    qaUnitTest('setThemeMode persists and notifies listeners', () async {
      final prefs = await _prefs();
      final provider = ThemeProvider(prefs);
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setThemeMode(ThemeMode.light);

      expect(provider.themeMode, ThemeMode.light);
      expect(prefs.themeMode, 'light');
      expect(notified, 1);
    });

    qaUnitTest('toggleTheme flips between dark and light', () async {
      final provider = ThemeProvider(await _prefs());

      await provider.toggleTheme();
      expect(provider.themeMode, ThemeMode.dark);

      await provider.toggleTheme();
      expect(provider.themeMode, ThemeMode.light);
    });
  });
}
