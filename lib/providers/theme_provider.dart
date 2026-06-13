import 'package:flutter/material.dart';

import '../core/services/shared_preferences_service.dart';

/// Manages theme mode with persistence.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) {
    _loadThemeMode();
  }

  final SharedPreferencesService _prefs;

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void _loadThemeMode() {
    final stored = _prefs.themeMode;
    if (stored == null) return;

    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setThemeMode(mode.name);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final next = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setThemeMode(next);
  }
}
