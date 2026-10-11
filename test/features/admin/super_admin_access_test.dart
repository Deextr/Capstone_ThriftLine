import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/admin_auth_redirect.dart';
import 'package:thriftline/core/routes/auth_redirect.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/features/admin/data/admin_account_models.dart';
import 'package:thriftline/features/admin/data/admin_portal_session.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/models/enums.dart';

AuthUser _user({
  UserRole role = UserRole.buyer,
  String accountStatus = 'active',
}) {
  return AuthUser(
    id: 'user-1',
    username: 'maya',
    name: 'Maya Cruz',
    email: 'maya@example.com',
    role: role,
    avatarUrl: '',
    location: 'Davao City',
    accountStatus: accountStatus,
  );
}

void main() {
  group('UserRole', () {
    test('parses super_admin without treating it as a buyer', () {
      expect(UserRole.fromString('super_admin'), UserRole.superAdmin);
      expect(UserRole.fromString('Super_Admin'), UserRole.superAdmin);
      expect(UserRole.superAdmin.dbValue, 'super_admin');
      expect(UserRole.superAdmin.isAdministrator, isTrue);
    });

    test('rejects an unknown role', () {
      expect(() => UserRole.fromString('owner'), throwsFormatException);
    });

    test('empty role stays buyer', () {
      expect(UserRole.fromString(''), UserRole.buyer);
    });
  });

  group('administrator access flags', () {
    test(
      'super admin is blocked from the marketplace and allowed on the portal',
      () {
        final user = _user(role: UserRole.superAdmin);
        expect(user.isAdmin, isTrue);
        expect(user.isSuperAdmin, isTrue);
        expect(user.canUseAdminPortal, isTrue);
        expect(user.isBuyer, isFalse);
        expect(user.isSeller, isFalse);
      },
    );

    test(
      'deactivated admin cannot use the portal but remains an administrator',
      () {
        final user = _user(role: UserRole.admin, accountStatus: 'deactivated');
        expect(user.isAdmin, isTrue);
        expect(user.canUseAdminPortal, isFalse);
        expect(user.isDeactivatedAdministrator, isTrue);
      },
    );

    test('buyer is not an administrator', () {
      final user = _user();
      expect(user.isAdmin, isFalse);
      expect(user.canUseAdminPortal, isFalse);
    });
  });

  group('mobile redirect', () {
    test('admin and super admin stay on the portal notice', () {
      for (final isAdmin in [true]) {
        expect(
          authenticatedWorkspaceRedirect(
            isAdmin: isAdmin,
            isSellerMode: false,
            isBuyerMode: true,
            location: RouteNames.buyerHome,
            homeRoute: RouteNames.buyerHome,
          ),
          RouteNames.adminPortalRequired,
        );
      }
    });
  });

  group('admin web redirect', () {
    String? redirect({
      required bool canUseAdminPortal,
      required bool isSuperAdmin,
      required String location,
      bool isDeactivatedAdministrator = false,
      bool isAuthenticated = true,
      bool isFullyAuthenticated = true,
    }) {
      return adminAppRedirect(
        isAuthenticated: isAuthenticated,
        canUseAdminPortal: canUseAdminPortal,
        isDeactivatedAdministrator: isDeactivatedAdministrator,
        isSuperAdmin: isSuperAdmin,
        isFullyAuthenticated: isFullyAuthenticated,
        isEmailOtpPending: false,
        location: location,
      );
    }

    test('buyer and seller cannot open the dashboard', () {
      expect(
        redirect(
          canUseAdminPortal: false,
          isSuperAdmin: false,
          location: RouteNames.adminDashboard,
        ),
        RouteNames.adminAccessDenied,
      );
    });

    test('deactivated admin sees the denied screen', () {
      expect(
        redirect(
          canUseAdminPortal: false,
          isSuperAdmin: false,
          isDeactivatedAdministrator: true,
          location: RouteNames.adminVerifications,
        ),
        RouteNames.adminAccessDenied,
      );
    });

    test('normal admin can open operations but not administration', () {
      expect(
        redirect(
          canUseAdminPortal: true,
          isSuperAdmin: false,
          location: RouteNames.adminVerifications,
        ),
        isNull,
      );
      expect(
        redirect(
          canUseAdminPortal: true,
          isSuperAdmin: false,
          location: RouteNames.adminAdministrators,
        ),
        RouteNames.adminDashboard,
      );
      expect(
        redirect(
          canUseAdminPortal: true,
          isSuperAdmin: false,
          location: RouteNames.adminLogs,
        ),
        RouteNames.adminDashboard,
      );
    });

    test('super admin can open administration', () {
      expect(
        redirect(
          canUseAdminPortal: true,
          isSuperAdmin: true,
          location: RouteNames.adminAdministrators,
        ),
        isNull,
      );
      expect(
        redirect(
          canUseAdminPortal: true,
          isSuperAdmin: true,
          location: RouteNames.adminLogs,
        ),
        isNull,
      );
    });

    test('unauthenticated visitors are sent to login', () {
      expect(
        redirect(
          canUseAdminPortal: false,
          isSuperAdmin: false,
          isAuthenticated: false,
          isFullyAuthenticated: false,
          location: RouteNames.adminDashboard,
        ),
        '${RouteNames.adminLogin}?redirect=${Uri.encodeComponent(RouteNames.adminDashboard)}',
      );
    });
  });

  group('admin invitation validation', () {
    test('normalizes email casing', () {
      expect(normalizeAdminEmail(' Example@Gmail.com '), 'example@gmail.com');
    });

    test('buyer and seller emails use the registered-account message', () {
      expect(
        adminInviteFailureMessage(code: 'buyer_or_seller'),
        adminInviteBuyerOrSellerMessage,
      );
    });

    test('admin, super admin, and auth-only identities are rejected', () {
      expect(
        adminInviteFailureMessage(code: 'administrator'),
        adminInviteExistingAccountMessage,
      );
      expect(
        adminInviteFailureMessage(code: 'auth_only'),
        adminInviteExistingAccountMessage,
      );
    });

    test('pending invitations are not duplicated', () {
      expect(
        adminInviteFailureMessage(code: 'invitation_pending'),
        adminInvitePendingMessage,
      );
    });
  });

  test('authorization failures are recognized for a session refresh', () {
    expect(
      isAdminAuthorizationFailure(Exception('super admin access required')),
      isTrue,
    );
    expect(
      isAdminAuthorizationFailure(Exception('Could not load accounts.')),
      isFalse,
    );
  });

  test('stale moderation decisions use one refresh message', () {
    expect(
      mapAdminDecisionError('This report has already been reviewed.'),
      kAdminStaleDecisionMessage,
    );
    expect(
      mapAdminDecisionError('pending verification 1 not found'),
      kAdminStaleDecisionMessage,
    );
  });
}
