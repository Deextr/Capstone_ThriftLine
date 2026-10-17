import 'package:flutter/material.dart';

import '../../../../core/routes/route_names.dart';

/// Single admin portal sidebar destination (route + presentation).
class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final int badge;
}

/// Group of related sidebar destinations under one heading.
class AdminNavSection {
  const AdminNavSection({
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final List<AdminNavItem> items;
}

bool adminSectionHasSelectedItem(String location, AdminNavSection section) {
  return section.items.any((i) => adminNavItemSelected(location, i.route));
}

int adminSectionBadgeTotal(AdminNavSection section) {
  var total = 0;
  for (final item in section.items) {
    total += item.badge;
  }
  return total;
}

/// Builds grouped admin sidebar navigation. All modules remain reachable; order
/// reflects typical daily workflow (overview → marketplace → payments → trust).
List<AdminNavSection> buildAdminSidebarSections({
  required bool isSuperAdmin,
  required int pendingVerifications,
  required int openDisputes,
  required int pendingPayouts,
  required int pendingBuyerRefunds,
}) {
  return [
    AdminNavSection(
      title: 'Overview',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      items: [
        const AdminNavItem(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          route: RouteNames.adminDashboard,
        ),
      ],
    ),
    AdminNavSection(
      title: 'Marketplace',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
      items: [
        AdminNavItem(
          label: 'Seller verifications',
          icon: Icons.verified_outlined,
          selectedIcon: Icons.verified_rounded,
          route: RouteNames.adminVerifications,
          badge: pendingVerifications,
        ),
        const AdminNavItem(
          label: 'Users',
          icon: Icons.people_outline,
          selectedIcon: Icons.people_rounded,
          route: RouteNames.adminUsers,
        ),
        const AdminNavItem(
          label: 'Reports',
          icon: Icons.assessment_outlined,
          selectedIcon: Icons.assessment_rounded,
          route: RouteNames.adminMarketplaceReports,
        ),
      ],
    ),
    AdminNavSection(
      title: 'Payments',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments_rounded,
      items: [
        const AdminNavItem(
          label: 'Orders & transactions',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          route: RouteNames.adminOrdersTransactions,
        ),
        AdminNavItem(
          label: 'Seller payouts',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          route: RouteNames.adminSellerPayouts,
          badge: pendingPayouts,
        ),
        AdminNavItem(
          label: 'Buyer refunds',
          icon: Icons.currency_exchange_outlined,
          selectedIcon: Icons.currency_exchange_rounded,
          route: RouteNames.adminBuyerRefunds,
          badge: pendingBuyerRefunds,
        ),
      ],
    ),
    AdminNavSection(
      title: 'Trust & safety',
      icon: Icons.shield_outlined,
      selectedIcon: Icons.shield_rounded,
      items: [
        const AdminNavItem(
          label: 'Bidding violations',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments_rounded,
          route: RouteNames.adminBiddingViolations,
        ),
        AdminNavItem(
          label: 'Disputes',
          icon: Icons.gavel_outlined,
          selectedIcon: Icons.gavel_rounded,
          route: RouteNames.adminReportsAll,
          badge: openDisputes,
        ),
      ],
    ),
    if (isSuperAdmin)
      const AdminNavSection(
        title: 'Administration',
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings_rounded,
        items: [
          AdminNavItem(
            label: 'Admin accounts',
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings_rounded,
            route: RouteNames.adminAdministrators,
          ),
          AdminNavItem(
            label: 'Activity logs',
            icon: Icons.history_outlined,
            selectedIcon: Icons.history_rounded,
            route: RouteNames.adminLogs,
          ),
        ],
      ),
  ];
}

bool adminNavItemSelected(String location, String target) {
  if (target == RouteNames.adminDashboard) {
    return location == RouteNames.adminDashboard ||
        location == RouteNames.adminHome;
  }
  if (target == RouteNames.adminOrdersTransactions) {
    return location.startsWith(RouteNames.adminOrdersTransactions) ||
        location.startsWith('${RouteNames.adminOrders}/') ||
        location == RouteNames.adminOrders ||
        location.startsWith(RouteNames.adminTransactions);
  }
  if (target == RouteNames.adminBiddingViolations) {
    return location.startsWith(RouteNames.adminBiddingViolations);
  }
  if (target == RouteNames.adminReportsAll ||
      target == RouteNames.adminReportsCommunity) {
    return (location.startsWith('/admin/reports/') &&
            location != RouteNames.adminReports) ||
        location.startsWith(RouteNames.adminDisputes) ||
        location.startsWith('/admin/looking-for-reports');
  }
  return location.startsWith(target);
}
