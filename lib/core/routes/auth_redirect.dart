import 'route_names.dart';

/// Stay on login/signup until the server answers the trusted-device check.
/// The pending flag is set before that answer so a crash cannot skip OTP,
/// and it must not open the OTP screen during the check.
bool holdAuthScreenForTrustedDeviceCheck({
  required bool resolvingTrustedDevice,
  required String location,
}) {
  if (!resolvingTrustedDevice) return false;
  return location == RouteNames.login ||
      location == RouteNames.emailLogin ||
      location == RouteNames.signup ||
      location == RouteNames.forgotPassword;
}

bool isPasswordRecoveryAuthRoute(String location) {
  return location == RouteNames.forgotPassword ||
      location == RouteNames.resetPassword;
}

/// Keeps the user on the reset screen while a recovery session is active.
String? passwordRecoveryWorkspaceRedirect({
  required bool recoveryActive,
  required String location,
}) {
  if (!recoveryActive) return null;
  if (location == RouteNames.resetPassword) return null;
  return RouteNames.resetPassword;
}

/// Routes reachable without a full session (login, signup, password recovery).
bool isPublicAuthRoute(String location) {
  return location == RouteNames.login ||
      location == RouteNames.emailLogin ||
      location == RouteNames.signup ||
      isPasswordRecoveryAuthRoute(location);
}

/// When email OTP is marked pending but there is no session yet, keep the
/// user on signup/login so a rejected registration can show its error.
/// Any other location goes to login.
String? unauthenticatedEmailOtpRedirect({
  required String location,
  required bool isAuthenticated,
  required bool emailOtpPending,
}) {
  if (!emailOtpPending || isAuthenticated) return null;
  if (location == RouteNames.signup ||
      location == RouteNames.login ||
      location == RouteNames.emailLogin) {
    return null;
  }
  return RouteNames.login;
}

/// Seller dashboard and listing tools. Public shop pages such as
/// `/seller-profile/:username` are intentionally excluded so buyers can
/// still view another seller's storefront.
bool isSellerWorkspaceLocation(String location) {
  if (location == RouteNames.sellerHome) return true;
  if (location == RouteNames.addListing) return true;
  if (location == RouteNames.myShop) return true;
  if (location == RouteNames.sellerAnalytics) return true;
  if (location == RouteNames.sellerShopAddress) return true;
  if (location == RouteNames.sellerMyRiders) return true;
  if (location == RouteNames.sellerSavedRiderEditor) return true;
  if (location.startsWith('/edit-listing/')) return true;
  if (location.startsWith('/seller-order/')) return true;
  return false;
}

/// After a full session exists, keep the user on the home that matches their
/// active Buyer/Seller workspace. Admins are not forced into either shell.
String? authenticatedWorkspaceRedirect({
  required bool isAdmin,
  required bool isSellerMode,
  required bool isBuyerMode,
  required String location,
  required String homeRoute,
}) {
  if (isAdmin) {
    if (location == RouteNames.adminPortalRequired) return null;
    return RouteNames.adminPortalRequired;
  }
  if (location.startsWith('/admin')) {
    return homeRoute;
  }
  if (isSellerMode && location == RouteNames.buyerHome) {
    return RouteNames.sellerHome;
  }
  if (isBuyerMode && isSellerWorkspaceLocation(location)) {
    return RouteNames.buyerHome;
  }
  return null;
}
