import 'package:flutter/material.dart';

/// Semantic ThriftLine theme tokens (Light / Dark).
///
/// Architecture:
/// - **Brand** (`brandPrimary`, `brandPrimaryDark`) — constant `#0D9488` teal.
/// - **Surfaces** — `background`, `sidebarSurface`, `surface`, `surfaceVariant`.
/// - **Content** — `textPrimary`, `textSecondary`, `textHint`.
/// - **Chrome** — `border`, `divider`, `primaryLight` (selection / chips).
/// - **Semantic** — warning / error soft fills and foregrounds.
/// - **Sign out** — dedicated destructive control colors.
///
/// Prefer [AppPalette.of] / [BuildContext.palette] inside `build`. The
/// [AppPalette.current] binding exists only for legacy [AppColors] getters and
/// is synchronized by [ThemeProvider] and [AdminThemeSync].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.sidebarSurface,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.border,
    required this.divider,
    required this.primaryLight,
    required this.warningSoft,
    required this.warningForeground,
    required this.errorSoft,
    required this.errorForeground,
    required this.neutralSoft,
    required this.signOutBackground,
    required this.signOutForeground,
    required this.signOutHover,
    required this.signOutBorder,
  });

  final Color background;
  final Color sidebarSurface;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color border;
  final Color divider;
  final Color primaryLight;
  final Color warningSoft;
  final Color warningForeground;
  final Color errorSoft;
  final Color errorForeground;
  final Color neutralSoft;
  final Color signOutBackground;
  final Color signOutForeground;
  final Color signOutHover;
  final Color signOutBorder;

  static const Color brandPrimary = Color(0xFF0D9488);
  static const Color brandPrimaryDark = Color(0xFF0F766E);
  static const Color brandSecondary = Color(0xFFF97316);

  static const AppPalette light = AppPalette(
    background: Color(0xFFF8FAFC),
    sidebarSurface: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textHint: Color(0xFF94A3B8),
    border: Color(0xFFE2E8F0),
    divider: Color(0xFFE2E8F0),
    primaryLight: Color(0xFFCCFBF1),
    warningSoft: Color(0xFFFEF3C7),
    warningForeground: Color(0xFF92400E),
    errorSoft: Color(0xFFFEF2F2),
    errorForeground: Color(0xFFDC2626),
    neutralSoft: Color(0xFFF1F5F9),
    signOutBackground: Color(0xFFFEF2F2),
    signOutForeground: Color(0xFFDC2626),
    signOutHover: Color(0xFFFEE2E2),
    signOutBorder: Color(0xFFFECACA),
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0F172A),
    sidebarSurface: Color(0xFF111827),
    surface: Color(0xFF1E293B),
    surfaceVariant: Color(0xFF334155),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textHint: Color(0xFF94A3B8),
    border: Color(0xFF334155),
    divider: Color(0xFF334155),
    primaryLight: Color(0xFF134E4A),
    warningSoft: Color(0xFF422006),
    warningForeground: Color(0xFFFBBF24),
    errorSoft: Color(0xFF450A0A),
    errorForeground: Color(0xFFF87171),
    neutralSoft: Color(0xFF1E293B),
    signOutBackground: Color(0xFF450A0A),
    signOutForeground: Color(0xFFF87171),
    signOutHover: Color(0xFF7F1D1D),
    signOutBorder: Color(0xFF7F1D1D),
  );

  /// Runtime palette bound before [MaterialApp] builds, so color getters
  /// resolve correctly on the first frame (no light-mode flash).
  static AppPalette current = light;

  static void bindBrightness(Brightness brightness) {
    current = brightness == Brightness.dark ? dark : light;
  }

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? current;
  }

  bool get isDark => identical(this, dark) || background == dark.background;

  @override
  AppPalette copyWith({
    Color? background,
    Color? sidebarSurface,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? border,
    Color? divider,
    Color? primaryLight,
    Color? warningSoft,
    Color? warningForeground,
    Color? errorSoft,
    Color? errorForeground,
    Color? neutralSoft,
    Color? signOutBackground,
    Color? signOutForeground,
    Color? signOutHover,
    Color? signOutBorder,
  }) {
    return AppPalette(
      background: background ?? this.background,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      primaryLight: primaryLight ?? this.primaryLight,
      warningSoft: warningSoft ?? this.warningSoft,
      warningForeground: warningForeground ?? this.warningForeground,
      errorSoft: errorSoft ?? this.errorSoft,
      errorForeground: errorForeground ?? this.errorForeground,
      neutralSoft: neutralSoft ?? this.neutralSoft,
      signOutBackground: signOutBackground ?? this.signOutBackground,
      signOutForeground: signOutForeground ?? this.signOutForeground,
      signOutHover: signOutHover ?? this.signOutHover,
      signOutBorder: signOutBorder ?? this.signOutBorder,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      sidebarSurface: Color.lerp(sidebarSurface, other.sidebarSurface, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningForeground: Color.lerp(
        warningForeground,
        other.warningForeground,
        t,
      )!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      errorForeground: Color.lerp(errorForeground, other.errorForeground, t)!,
      neutralSoft: Color.lerp(neutralSoft, other.neutralSoft, t)!,
      signOutBackground: Color.lerp(
        signOutBackground,
        other.signOutBackground,
        t,
      )!,
      signOutForeground: Color.lerp(
        signOutForeground,
        other.signOutForeground,
        t,
      )!,
      signOutHover: Color.lerp(signOutHover, other.signOutHover, t)!,
      signOutBorder: Color.lerp(signOutBorder, other.signOutBorder, t)!,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => AppPalette.of(this);
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
}
