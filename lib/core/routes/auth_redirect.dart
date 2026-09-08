import 'route_names.dart';

/// When email OTP is marked pending but there is no session yet, keep the
/// user on signup/login so a rejected registration can show its error.
/// Any other location goes to login.
String? unauthenticatedEmailOtpRedirect({
  required String location,
  required bool isAuthenticated,
  required bool emailOtpPending,
}) {
  if (!emailOtpPending || isAuthenticated) return null;
  if (location == RouteNames.signup || location == RouteNames.login) {
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
  if (location.startsWith('/admin') && !isAdmin) {
    return homeRoute;
  }
  if (isAdmin) return null;
  if (isSellerMode && location == RouteNames.buyerHome) {
    return RouteNames.sellerHome;
  }
  if (isBuyerMode && isSellerWorkspaceLocation(location)) {
    return RouteNames.buyerHome;
  }
  return null;
}
