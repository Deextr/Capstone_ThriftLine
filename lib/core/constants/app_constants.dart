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
  static const String keyEmailOtpPending = 'email_otp_pending';

  /// Survives process death while the user has not finished reset-password.
  static const String keyPasswordRecoveryPending = 'password_recovery_pending';

  /// Open PayMongo hosted checkout — cleared after paid or terminal failure.
  static const String keyPaymongoPendingOrderId = 'paymongo_pending_order_id';
  static const String keyPaymongoPendingCheckoutGroupId =
      'paymongo_pending_checkout_group_id';
  static const String keyPaymongoPendingStartedAtMs =
      'paymongo_pending_started_at_ms';

  /// Non-secret marker that pairs with the secure-storage install token.
  /// Logout must keep it. It is not a credential and must not be the token.
  static const String keyDeviceTrustInstall = 'device_trust_install';
  static const String keyActiveAccount = 'active_account';
  static const String keyActiveAccountUserId = 'active_account_user_id';
  static const String keyRecentSearchesPrefix = 'recent_searches_';
  static const String keyBuyerHomeCache = 'buyer_home_feed_cache';
  static const String keyAdminDashboardCache = 'admin_dashboard_snapshot';

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

  // Default Fallbacks
  static const String defaultAvatarUrl =
      'https://ui-avatars.com/api/?name=User&background=6C5CE7&crolor=ffffff&size=150';
}
