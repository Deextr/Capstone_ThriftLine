import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';

void main() {
  group('Authorization policy', () {
    test('AUTHZ-001 buyer can access buyer functions', () {
      expect(
        homeRouteFor(
          isAdmin: false,
          activeAccount: AccountMode.buyer,
        ),
        RouteNames.buyerHome,
      );
      expect(
        resolveAccountMode(
          hasSellerAccess: false,
          isAdmin: false,
          restoreFromPrefs: true,
        ),
        AccountMode.buyer,
      );
    });

    test('AUTHZ-002 approved seller can access seller functions', () {
      expect(
        authHasSellerAccess(isVerified: true, roleIsSeller: false),
        isTrue,
      );
      expect(
        homeRouteFor(
          isAdmin: false,
          activeAccount: AccountMode.seller,
        ),
        RouteNames.sellerHome,
      );
    });

    test('AUTHZ-003 admin can access admin functions', () {
      expect(
        homeRouteFor(
          isAdmin: true,
          activeAccount: AccountMode.buyer,
        ),
        RouteNames.adminHome,
      );
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: true,
          isSellerMode: false,
          isBuyerMode: false,
          location: RouteNames.adminHome,
          homeRoute: RouteNames.adminHome,
        ),
        RouteNames.adminPortalRequired,
      );
    });

    test('AUTHZ-004 buyer cannot access admin functions', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: RouteNames.adminHome,
          homeRoute: RouteNames.buyerHome,
        ),
        RouteNames.buyerHome,
      );
    });

    test('AUTHZ-005 seller cannot access admin functions', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: true,
          isBuyerMode: false,
          location: RouteNames.adminHome,
          homeRoute: RouteNames.sellerHome,
        ),
        RouteNames.sellerHome,
      );
    });
  });
}
