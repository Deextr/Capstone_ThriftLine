import 'route_names.dart';

bool isAdminPublicRoute(String location) {
  return location == RouteNames.adminLogin ||
      location == RouteNames.adminVerifyEmailOtp ||
      location == RouteNames.adminAccessDenied ||
      location == RouteNames.adminAcceptInvite;
}

bool isSuperAdminOnlyRoute(String location) {
  return location.startsWith(RouteNames.adminAdministrators) ||
      location.startsWith(RouteNames.adminLogs);
}

bool holdAdminLoginForTrustedDeviceCheck({
  required bool resolvingTrustedDevice,
  required String location,
}) {
  if (!resolvingTrustedDevice) return false;
  return location == RouteNames.adminLogin;
}

bool isAdminProtectedRoute(String location) {
  if (!location.startsWith('/admin')) return false;
  return !isAdminPublicRoute(location);
}

/// Admin web router: keep unauthenticated users on login; block non-admins.
String? adminAppRedirect({
  required bool isAuthenticated,
  required bool canUseAdminPortal,
  required bool isDeactivatedAdministrator,
  required bool isSuperAdmin,
  required bool isFullyAuthenticated,
  required bool isEmailOtpPending,
  required String location,
}) {
  if (location == '/' || location.isEmpty) {
    return RouteNames.adminLogin;
  }

  final isLogin = location == RouteNames.adminLogin;
  final isVerifyEmailOtp = location == RouteNames.adminVerifyEmailOtp;
  final isDenied = location == RouteNames.adminAccessDenied;

  if (location == RouteNames.adminAcceptInvite) return null;

  if (location == RouteNames.adminHome) {
    return RouteNames.adminDashboard;
  }

  if (isEmailOtpPending) {
    if (!isAuthenticated) {
      if (isLogin || isVerifyEmailOtp) return null;
      return RouteNames.adminLogin;
    }
    if (!isVerifyEmailOtp) return RouteNames.adminVerifyEmailOtp;
    return null;
  }

  if (!isAuthenticated && isDenied) {
    return RouteNames.adminLogin;
  }

  if (!isAuthenticated && isAdminProtectedRoute(location)) {
    final redirect = Uri.encodeComponent(location);
    return '${RouteNames.adminLogin}?redirect=$redirect';
  }

  if (isFullyAuthenticated && (isLogin || isVerifyEmailOtp)) {
    if (canUseAdminPortal) return RouteNames.adminDashboard;
    // Stay on login so a marketplace session can be replaced with admin credentials.
    if (isLogin) return null;
    return RouteNames.adminAccessDenied;
  }

  if (isFullyAuthenticated && !canUseAdminPortal) {
    if (isDenied) return null;
    if (isAdminProtectedRoute(location) || isLogin) {
      return RouteNames.adminAccessDenied;
    }
  }

  if (isFullyAuthenticated && canUseAdminPortal && isDenied) {
    return RouteNames.adminDashboard;
  }

  if (isFullyAuthenticated &&
      canUseAdminPortal &&
      !isSuperAdmin &&
      isSuperAdminOnlyRoute(location)) {
    return RouteNames.adminDashboard;
  }

  if (isDeactivatedAdministrator && isDenied) return null;

  return null;
}
