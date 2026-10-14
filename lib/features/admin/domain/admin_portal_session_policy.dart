import '../../../../providers/auth_provider.dart';

/// Inactivity timeout for authenticated administrators in the Admin Web Portal.
const Duration adminPortalInactivityTimeout = Duration(minutes: 10);

const String adminPortalInactivityLogoutMessage =
    'You have been signed out due to 10 minutes of inactivity. Please sign in again.';

const String adminPortalForgetDeviceLogoutMessage =
    'Logged out. This browser will ask for an email code next time.';

/// Whether the portal should track user activity and enforce inactivity logout.
///
/// OTP and other incomplete gates must not start the idle clock. A password
/// success that still needs email verification is not a usable admin session.
bool shouldMonitorAdminPortalSession(AuthProvider auth) {
  if (!auth.isInitialized) return false;
  if (!auth.isFullyAuthenticated) return false;
  return auth.canUseAdminPortal;
}

/// Activity timestamp used when monitoring begins.
///
/// A restored browser session may reuse a stored clock so an idle refresh
/// still expires. A new sign-in must start from [nowMs] so a leftover
/// timestamp from a previous logout cannot immediately time out the login.
int resolveAdminPortalMonitorStartMs({
  required int storedActivityMs,
  required int nowMs,
  required bool reuseStoredActivity,
}) {
  if (reuseStoredActivity && storedActivityMs > 0) return storedActivityMs;
  return nowMs;
}

/// Minimum gap between persisting activity timestamps (cross-tab sync).
const Duration adminPortalActivityPersistThrottle = Duration(seconds: 2);
