import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/shared_preferences_service.dart';
import '../core/theme/app_palette.dart';

/// Manages theme mode with persistence.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) {
    _loadThemeMode();
    AppPalette.bindBrightness(_resolvedBrightness);
  }

  final SharedPreferencesService _prefs;

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode =>
      _themeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Brightness get _resolvedBrightness =>
      _themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light;

  void _loadThemeMode() {
    final stored = _prefs.themeMode;
    if (stored == null) return;

    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.light,
    );
    if (_themeMode == ThemeMode.system) {
      _themeMode = ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final next = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
    unawaited(_prefs.setThemeMode(next.name));
  }

  Future<void> toggleTheme() async {
    await setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }
}
