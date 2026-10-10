import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

abstract final class AppColors {
  static const Color primary = AppPalette.brandPrimary;
  static const Color primaryDark = AppPalette.brandPrimaryDark;

  static const Color secondary = AppPalette.brandSecondary;
  static const Color accent = AppPalette.brandSecondary;

  /// Soft teal fill. Adapts so Light Mode keeps the mint chip and Dark Mode
  /// uses a deep teal that still reads as a selection state.
  static Color get primaryLight => AppPalette.current.primaryLight;

  static Color get background => AppPalette.current.background;
  static Color get sidebarSurface => AppPalette.current.sidebarSurface;
  static Color get surface => AppPalette.current.surface;
  static Color get surfaceVariant => AppPalette.current.surfaceVariant;

  static Color get textPrimary => AppPalette.current.textPrimary;
  static Color get textSecondary => AppPalette.current.textSecondary;
  static Color get textHint => AppPalette.current.textHint;

  static Color get border => AppPalette.current.border;
  static Color get divider => AppPalette.current.divider;

  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  static Color get warningSoft => AppPalette.current.warningSoft;
  static Color get warningForeground => AppPalette.current.warningForeground;
  static Color get errorSoft => AppPalette.current.errorSoft;
  static Color get errorForeground => AppPalette.current.errorForeground;
  static Color get neutralSoft => AppPalette.current.neutralSoft;
}
