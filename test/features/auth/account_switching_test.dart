import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/models/enums.dart';

AuthUser _user({
  UserRole role = UserRole.buyer,
  bool isVerified = false,
  String? shopName,
}) {
  return AuthUser(
    id: 'user-1',
    username: 'maya',
    name: 'Maya Cruz',
    email: 'maya@example.com',
    role: role,
    avatarUrl: '',
    location: 'Davao City',
    shopName: shopName,
    isVerified: isVerified,
  );
}

void main() {
  group('seller access', () {
    test('buyers without approval cannot switch', () {
      final user = _user();
      expect(user.hasSellerAccess, isFalse);
      expect(
        authCanSwitchAccounts(
          hasSellerAccess: user.hasSellerAccess,
          isAdmin: false,
        ),
        isFalse,
      );
    });

    test('admin approval via seller role unlocks both workspaces', () {
      final user = _user(role: UserRole.seller);
      expect(user.hasSellerAccess, isTrue);
      expect(
        authCanSwitchAccounts(
          hasSellerAccess: user.hasSellerAccess,
          isAdmin: false,
        ),
        isTrue,
      );
    });

    test(
      'approved seller_profiles flag unlocks switching even if role lags',
      () {
        final user = _user(isVerified: true);
        expect(user.hasSellerAccess, isTrue);
      },
    );

    test('admins do not use Buyer/Seller switching', () {
      expect(
        authCanSwitchAccounts(hasSellerAccess: true, isAdmin: true),
        isFalse,
      );
    });
  });

  group('resolveAccountMode', () {
    test('plain buyers stay on the buyer workspace', () {
      expect(
        resolveAccountMode(
          hasSellerAccess: false,
          isAdmin: false,
          restoreFromPrefs: true,
        ),
        AccountMode.buyer,
      );
    });

    test('approved sellers default to seller on first login', () {
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          restoreFromPrefs: true,
        ),
        AccountMode.seller,
      );
    });

    test('restores the last workspace for the same user', () {
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          savedMode: 'buyer',
          restoreFromPrefs: true,
        ),
        AccountMode.buyer,
      );
    });

    test('keeps the current workspace after a profile reload', () {
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          currentMode: AccountMode.buyer,
          restoreFromPrefs: false,
        ),
        AccountMode.buyer,
      );
    });
  });

  group('homeRouteFor', () {
    test('admins stay on the admin shell', () {
      expect(
        homeRouteFor(isAdmin: true, activeAccount: AccountMode.seller),
        RouteNames.adminHome,
      );
    });

    test('active mode selects buyer or seller home', () {
      expect(
        homeRouteFor(isAdmin: false, activeAccount: AccountMode.buyer),
        RouteNames.buyerHome,
      );
      expect(
        homeRouteFor(isAdmin: false, activeAccount: AccountMode.seller),
        RouteNames.sellerHome,
      );
    });
  });

  group('authenticatedWorkspaceRedirect', () {
    test('keeps a seller-mode user off the buyer shell', () {
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

    test('keeps a buyer-mode dual user off seller tools', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: RouteNames.sellerHome,
          homeRoute: RouteNames.buyerHome,
        ),
        RouteNames.buyerHome,
      );
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: false,
          isSellerMode: false,
          isBuyerMode: true,
          location: RouteNames.addListing,
          homeRoute: RouteNames.buyerHome,
        ),
        RouteNames.buyerHome,
      );
    });

    test('still allows buyers to open a public seller profile', () {
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

    test('does not merge or rewrite admin into a marketplace shell', () {
      expect(
        authenticatedWorkspaceRedirect(
          isAdmin: true,
          isSellerMode: false,
          isBuyerMode: false,
          location: RouteNames.adminHome,
          homeRoute: RouteNames.adminHome,
        ),
        isNull,
      );
    });
  });

  group('active account prefs', () {
    test('stores mode per user and does not leak to another login', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      await prefs.setActiveAccount(userId: 'user-1', mode: 'buyer');
      expect(prefs.activeAccountFor('user-1'), 'buyer');
      expect(prefs.activeAccountFor('user-2'), isNull);

      await prefs.clearAuthSession();
      expect(prefs.activeAccountFor('user-1'), 'buyer');
    });

    test('uses dedicated keys so logout does not drop dual-role memory', () {
      expect(AppConstants.keyActiveAccount, 'active_account');
      expect(AppConstants.keyActiveAccountUserId, 'active_account_user_id');
    });

    test('stores recent searches per user', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      await prefs.setRecentSearches('user-1', ['denim']);
      expect(prefs.recentSearchesFor('user-1'), ['denim']);
      expect(prefs.recentSearchesFor('user-2'), isEmpty);
    });
  });

  group('canEditOwnPublicShop', () {
    test('buyer workspace cannot edit their own public shop', () {
      expect(
        canEditOwnPublicShop(isOwnShop: true, isSellerWorkspace: false),
        isFalse,
      );
    });

    test('seller workspace can edit their own public shop', () {
      expect(
        canEditOwnPublicShop(isOwnShop: true, isSellerWorkspace: true),
        isTrue,
      );
    });

    test('nobody edits another seller shop from this control', () {
      expect(
        canEditOwnPublicShop(isOwnShop: false, isSellerWorkspace: true),
        isFalse,
      );
    });
  });

  group('isSellerWorkspaceLocation', () {
    test('covers seller tools only', () {
      expect(isSellerWorkspaceLocation(RouteNames.sellerHome), isTrue);
      expect(isSellerWorkspaceLocation(RouteNames.myShop), isTrue);
      expect(isSellerWorkspaceLocation('/edit-listing/abc'), isTrue);
      expect(isSellerWorkspaceLocation('/seller-order/abc'), isTrue);
      expect(isSellerWorkspaceLocation('/seller-profile/abc'), isFalse);
      expect(isSellerWorkspaceLocation('/looking-for/abc'), isFalse);
      expect(isSellerWorkspaceLocation('/chat/abc'), isFalse);
      expect(isSellerWorkspaceLocation(RouteNames.buyerHome), isFalse);
    });
  });
}
