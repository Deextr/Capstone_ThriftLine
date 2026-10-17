import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/features/admin/presentation/web/admin_sidebar_nav.dart';

void main() {
  group('buildAdminSidebarSections', () {
    test('groups all standard modules without losing routes', () {
      final sections = buildAdminSidebarSections(
        isSuperAdmin: false,
        pendingVerifications: 2,
        openDisputes: 1,
        pendingPayouts: 3,
        pendingBuyerRefunds: 4,
      );

      expect(sections.map((s) => s.title), [
        'Overview',
        'Marketplace',
        'Payments',
        'Trust & safety',
      ]);

      final routes = sections
          .expand((s) => s.items)
          .map((i) => i.route)
          .toList();
      expect(routes, [
        RouteNames.adminDashboard,
        RouteNames.adminVerifications,
        RouteNames.adminUsers,
        RouteNames.adminMarketplaceReports,
        RouteNames.adminOrdersTransactions,
        RouteNames.adminSellerPayouts,
        RouteNames.adminBuyerRefunds,
        RouteNames.adminBiddingViolations,
        RouteNames.adminReportsAll,
      ]);

      final verifications = sections[1].items.first;
      expect(verifications.badge, 2);
      expect(sections[2].items[1].badge, 3);
      expect(sections[2].items[2].badge, 4);
      expect(sections[3].items.last.badge, 1);
    });

    test('appends administration section for super admins', () {
      final sections = buildAdminSidebarSections(
        isSuperAdmin: true,
        pendingVerifications: 0,
        openDisputes: 0,
        pendingPayouts: 0,
        pendingBuyerRefunds: 0,
      );

      expect(sections.last.title, 'Administration');
      expect(sections.last.items.map((i) => i.route), [
        RouteNames.adminAdministrators,
        RouteNames.adminLogs,
      ]);
    });
  });

  group('adminSectionHasSelectedItem', () {
    test('detects active child route inside a section', () {
      final sections = buildAdminSidebarSections(
        isSuperAdmin: false,
        pendingVerifications: 0,
        openDisputes: 0,
        pendingPayouts: 0,
        pendingBuyerRefunds: 0,
      );
      final marketplace = sections[1];
      expect(
        adminSectionHasSelectedItem(RouteNames.adminUsers, marketplace),
        isTrue,
      );
      expect(
        adminSectionHasSelectedItem(RouteNames.adminDashboard, marketplace),
        isFalse,
      );
    });
  });

  group('adminNavItemSelected', () {
    test('matches dashboard home aliases', () {
      expect(
        adminNavItemSelected(RouteNames.adminHome, RouteNames.adminDashboard),
        isTrue,
      );
      expect(
        adminNavItemSelected(
          '/admin/orders',
          RouteNames.adminOrdersTransactions,
        ),
        isTrue,
      );
      expect(
        adminNavItemSelected(
          '/admin/disputes/open',
          RouteNames.adminReportsAll,
        ),
        isTrue,
      );
    });
  });
}
