import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_users_service.dart';
import 'package:thriftline/features/admin/domain/marketplace_user_management.dart';
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
  group('marketplace directory rules', () {
    test('lists buyers and sellers and excludes administrators', () {
      expect(marketplaceRoleIsListed('buyer'), isTrue);
      expect(marketplaceRoleIsListed('seller'), isTrue);
      expect(marketplaceRoleIsListed('admin'), isFalse);
      expect(marketplaceRoleIsListed('super_admin'), isFalse);
    });

    test('labels one account as buyer or buyer and seller', () {
      expect(marketplaceAccountTypeLabel('buyer'), 'Buyer');
      expect(marketplaceAccountTypeLabel('buyer_seller'), 'Buyer & Seller');
    });

    test('account type filters use buyer-only and dual-mode buckets', () {
      expect(
        marketplaceAccountMatchesTypeFilter(
          accountType: 'buyer',
          filter: 'buyer',
        ),
        isTrue,
      );
      expect(
        marketplaceAccountMatchesTypeFilter(
          accountType: 'buyer_seller',
          filter: 'buyer',
        ),
        isFalse,
      );
      expect(
        marketplaceAccountMatchesTypeFilter(
          accountType: 'buyer_seller',
          filter: 'both',
        ),
        isTrue,
      );
    });

    test('search matches name, email, and username', () {
      expect(
        marketplaceAccountMatchesSearch(
          fullName: 'Maya Cruz',
          email: 'maya@example.com',
          username: 'maya',
          search: 'MAYA@example.com',
        ),
        isTrue,
      );
      expect(
        marketplaceAccountMatchesSearch(
          fullName: 'Maya Cruz',
          email: 'maya@example.com',
          username: 'maya',
          search: 'other',
        ),
        isFalse,
      );
    });

    test('trust Banned displays as banned and cannot be disabled again', () {
      expect(
        marketplaceEffectiveAccountStatus(
          accountStatus: 'active',
          trustLevel: 'Banned',
        ),
        'banned',
      );
      expect(
        canDisableMarketplaceAccount(
          role: 'seller',
          accountStatus: 'active',
          trustLevel: 'Banned',
        ),
        isFalse,
      );
    });

    test('status filters use stored values and disabled is suspended', () {
      expect(marketplaceAccountStatusLabel('active'), 'Active');
      expect(marketplaceAccountStatusLabel('suspended'), 'Disabled');
      expect(marketplaceAccountStatusLabel('banned'), 'Banned');
      expect(marketplaceAccountStatusLabel('deactivated'), 'Deactivated');
      expect(
        marketplaceAccountMatchesStatusFilter(
          accountStatus: 'suspended',
          filter: 'suspended',
        ),
        isTrue,
      );
      expect(
        marketplaceAccountMatchesStatusFilter(
          accountStatus: 'banned',
          filter: 'suspended',
        ),
        isFalse,
      );
      expect(
        marketplaceAccountMatchesStatusFilter(
          accountStatus: 'banned',
          filter: 'banned',
        ),
        isTrue,
      );
    });
  });

  group('disable eligibility', () {
    test('an active buyer or seller can be disabled', () {
      expect(
        canDisableMarketplaceAccount(role: 'buyer', accountStatus: 'active'),
        isTrue,
      );
      expect(
        canDisableMarketplaceAccount(role: 'seller', accountStatus: 'active'),
        isTrue,
      );
      expect(
        marketplaceDisableBlockedMessage(
          role: 'buyer',
          accountStatus: 'active',
        ),
        isNull,
      );
    });

    test(
      'disabled, banned, and administrator accounts cannot be disabled again',
      () {
        expect(
          canDisableMarketplaceAccount(
            role: 'buyer',
            accountStatus: 'suspended',
          ),
          isFalse,
        );
        expect(
          marketplaceDisableBlockedMessage(
            role: 'seller',
            accountStatus: 'suspended',
          ),
          'Account already disabled. No further disabling action is available.',
        );
        expect(
          canDisableMarketplaceAccount(role: 'buyer', accountStatus: 'banned'),
          isFalse,
        );
        expect(
          marketplaceDisableBlockedMessage(
            role: 'buyer',
            accountStatus: 'banned',
          ),
          'Account banned. This account is already restricted.',
        );
        expect(
          canDisableMarketplaceAccount(role: 'admin', accountStatus: 'active'),
          isFalse,
        );
        expect(
          canDisableMarketplaceAccount(
            role: 'super_admin',
            accountStatus: 'active',
          ),
          isFalse,
        );
      },
    );

    test('only the predefined reasons are accepted', () {
      expect(
        marketplaceDisableReasonAllowed('Fraudulent or suspicious activity'),
        isTrue,
      );
      expect(marketplaceDisableReasonAllowed('Because I said so'), isFalse);
      expect(marketplaceDisableReasons, hasLength(6));
    });
  });

  group('parsed directory rows', () {
    test(
      'keeps one row and ignores a server disable flag on a banned account',
      () {
        final row = MarketplaceUserRow.fromJson({
          'user_id': 'u1',
          'full_name': 'Maya Cruz',
          'email': 'maya@example.com',
          'username': 'maya',
          'role': 'seller',
          'account_status': 'banned',
          'account_type': 'buyer_seller',
          'created_at': '2026-01-02T00:00:00Z',
          'seller_approved': true,
          'can_disable': true,
          'verification_status': 'approved',
          'shop_name': 'Maya Studio',
        });

        expect(row.accountTypeLabel, 'Buyer & Seller');
        expect(row.statusLabel, 'Banned');
        expect(row.mayDisable, isFalse);
        expect(row.canDisable, isFalse);
        expect(row.sellerApproved, isTrue);
      },
    );

    test('global counts are separate from the filtered total', () {
      final counts = MarketplaceUserCounts.fromJson({
        'total': 10,
        'active': 7,
        'disabled': 2,
        'banned': 1,
      });
      expect(counts.total, 10);
      expect(counts.disabled, 2);
      expect(counts.banned, 1);
    });
  });

  group('restricted marketplace sessions', () {
    test('a disabled buyer is signed out and a banned buyer stays distinct', () {
      expect(
        _user(accountStatus: 'suspended').sessionBlockMessage,
        'Your account has been restricted. Marketplace seller activities are unavailable.',
      );
      expect(
        _user(accountStatus: 'banned').sessionBlockMessage,
        'This account has been permanently disabled.',
      );
      expect(_user().sessionBlockMessage, isNull);
    });

    test(
      'a deactivated administrator is not treated as a marketplace disable',
      () {
        final admin = _user(role: UserRole.admin, accountStatus: 'deactivated');
        expect(admin.sessionBlockMessage, isNull);
        expect(admin.canUseAdminPortal, isFalse);
        expect(admin.isDeactivatedAdministrator, isTrue);
      },
    );
  });
}
