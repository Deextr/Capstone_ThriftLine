import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';

void main() {
  group('unauthenticatedEmailOtpRedirect', () {
    test('redirects unauthenticated users to login', () {
      expect(
        unauthenticatedEmailOtpRedirect(
          location: RouteNames.buyerHome,
          isAuthenticated: false,
          emailOtpPending: true,
        ),
        RouteNames.login,
      );
    });

    test('keeps unauthenticated users on login and signup', () {
      for (final location in [RouteNames.login, RouteNames.signup]) {
        expect(
          unauthenticatedEmailOtpRedirect(
            location: location,
            isAuthenticated: false,
            emailOtpPending: true,
          ),
          isNull,
        );
      }
    });

    test('does not redirect when OTP is not pending or session exists', () {
      expect(
        unauthenticatedEmailOtpRedirect(
          location: RouteNames.buyerHome,
          isAuthenticated: false,
          emailOtpPending: false,
        ),
        isNull,
      );
      expect(
        unauthenticatedEmailOtpRedirect(
          location: RouteNames.buyerHome,
          isAuthenticated: true,
          emailOtpPending: true,
        ),
        isNull,
      );
    });
  });

  group('authenticatedWorkspaceRedirect', () {
    test('allows a buyer to access the buyer workspace', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: RouteNames.buyerHome,
          homeRoute: RouteNames.buyerHome,
        ),
        isNull,
      );
    });

    test('redirects a buyer away from seller tools', () {
      for (final location in [
        RouteNames.sellerHome,
        RouteNames.addListing,
        RouteNames.myShop,
        '/edit-listing/item-1',
        '/seller-order/order-1',
      ]) {
        expect(
          authenticatedWorkspaceRedirect(
            isAdmin: false,
            isSellerMode: false,
            isBuyerMode: true,
            location: location,
            homeRoute: RouteNames.buyerHome,
          ),
          RouteNames.buyerHome,
          reason: 'Buyer should not access $location',
        );
      }
    });

    test('allows a seller to access the seller workspace', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: true,
          isBuyerMode: false,
          location: RouteNames.sellerHome,
          homeRoute: RouteNames.sellerHome,
        ),
        isNull,
      );
    });

    test('redirects seller-mode users away from the buyer shell', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: true,
          isBuyerMode: false,
          location: RouteNames.buyerHome,
          homeRoute: RouteNames.sellerHome,
        ),
        RouteNames.sellerHome,
      );
    });

    test('allows approved dual-role users to use buyer mode', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: RouteNames.buyerHome,
          homeRoute: RouteNames.buyerHome,
        ),
        isNull,
      );
    });

    test('allows buyers to view public seller profiles', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: '/seller-profile/maya-shop',
          homeRoute: RouteNames.buyerHome,
        ),
        isNull,
      );
    });

    test('sends admins to the portal notice instead of the marketplace', () {
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

    test('redirects non-admin users away from admin routes', () {
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
  });

  group('isSellerWorkspaceLocation', () {
    test('recognizes seller tools but not public seller profiles', () {
      expect(isSellerWorkspaceLocation(RouteNames.sellerHome), isTrue);
      expect(isSellerWorkspaceLocation(RouteNames.addListing), isTrue);
      expect(isSellerWorkspaceLocation(RouteNames.myShop), isTrue);
      expect(isSellerWorkspaceLocation('/edit-listing/item-1'), isTrue);
      expect(isSellerWorkspaceLocation('/seller-order/order-1'), isTrue);
      expect(isSellerWorkspaceLocation('/seller-profile/maya-shop'), isFalse);
      expect(isSellerWorkspaceLocation(RouteNames.buyerHome), isFalse);
    });
  });
}
