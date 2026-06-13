/// Application-wide constant values.
abstract final class AppConstants {
  static const String appName = 'Thriftline';
  static const String appTagline = 'Buy & sell pre-loved treasures';

  // SharedPreferences keys
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyThemeMode = 'theme_mode';
  static const String keyUserRole = 'user_role';
  static const String keyUsername = 'username';
  static const String keyUserId = 'user_id';
  static const String keyDisplayName = 'display_name';

  // Breakpoints (mobile-first)
  static const double breakpointTablet = 600;
  static const double breakpointDesktop = 1024;
  static const double maxContentWidth = 1200;

  // Spacing scale
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacingXxl = 48;

  // Border radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
}
