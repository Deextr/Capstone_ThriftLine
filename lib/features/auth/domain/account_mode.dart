import '../../../core/routes/route_names.dart';

/// UI workspace the signed-in user is currently using.
///
/// This is not a second login and is not `users.role`. After admin approval the
/// same `auth.users` / `public.users` row may use both modes. Database role and
/// `seller_profiles.is_approved` stay the source of seller capability; this
/// value only chooses Buyer vs Seller chrome, navigation, and feature surfaces.
enum AccountMode {
  buyer,
  seller;

  static AccountMode? fromName(String? value) {
    return switch (value) {
      'buyer' => AccountMode.buyer,
      'seller' => AccountMode.seller,
      _ => null,
    };
  }
}

/// Whether this authenticated person may open the seller workspace.
///
/// [isVerified] comes from `seller_profiles.is_approved`. [roleIsSeller] is
/// `users.role = seller` after `review_seller_verification`. Either is enough
/// so a briefly stale field still unlocks switching.
bool authHasSellerAccess({
  required bool isVerified,
  required bool roleIsSeller,
}) => isVerified || roleIsSeller;

bool authCanSwitchAccounts({
  required bool hasSellerAccess,
  required bool isAdmin,
}) => hasSellerAccess && !isAdmin;

/// Picks the workspace after login, reload, or a missing preference.
///
/// Buyers and admins always resolve to [AccountMode.buyer] (admins use
/// [homeRouteFor] separately). Approved sellers restore the last saved mode,
/// or land on seller the first time — matching the previous single-role home.
AccountMode resolveAccountMode({
  required bool hasSellerAccess,
  required bool isAdmin,
  String? savedMode,
  AccountMode? currentMode,
  required bool restoreFromPrefs,
}) {
  if (isAdmin || !hasSellerAccess) return AccountMode.buyer;
  if (restoreFromPrefs) {
    return AccountMode.fromName(savedMode) ?? AccountMode.seller;
  }
  return currentMode ?? AccountMode.seller;
}

/// Edit controls on a public shop belong to the Seller workspace only.
///
/// The same person can open their shop while in Buyer mode; that visit is a
/// public view, not shop management.
bool canEditOwnPublicShop({
  required bool isOwnShop,
  required bool isSellerWorkspace,
}) => isOwnShop && isSellerWorkspace;

String homeRouteFor({
  required bool isAdmin,
  required AccountMode activeAccount,
}) {
  if (isAdmin) return RouteNames.adminHome;
  return activeAccount == AccountMode.seller
      ? RouteNames.sellerHome
      : RouteNames.buyerHome;
}
