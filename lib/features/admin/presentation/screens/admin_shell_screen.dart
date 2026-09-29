import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../widgets/curved_navigation_bar.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../controllers/admin_seller_applications_controller.dart';
import 'admin_dashboard_tab.dart';
import 'admin_reports_queue_screen.dart';
import 'admin_seller_applications_screen.dart';
import 'admin_tab_scope.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  void _onTabChanged(int newIndex) {
    if (newIndex == _index) return;
    setState(() => _index = newIndex);
    if (newIndex == AdminTabScope.dashboard) {
      context.read<AdminDashboardController>().load();
    }
    if (newIndex == AdminTabScope.verifications) {
      context.read<AdminSellerApplicationsController>().load();
    }
    if (newIndex == AdminTabScope.reports) {
      context.read<AdminReportsController>().load();
    }
  }

  Widget _page(int index) {
    return switch (index) {
      AdminTabScope.verifications => const AdminSellerApplicationsScreen(
        embedded: true,
      ),
      AdminTabScope.reports => const AdminReportsQueueScreen(embedded: true),
      AdminTabScope.settings => const SettingsScreen(
        showBackButton: false,
        showLogout: true,
      ),
      _ => const AdminDashboardTab(),
    };
  }

  Widget? _badge(int count) {
    if (count <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<AdminDashboardController>().counts;
    final pending = counts?.pendingVerifications ?? 0;
    final openReports = counts?.openReports ?? 0;
    final wide =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final page = KeyedSubtree(key: ValueKey<int>(_index), child: _page(_index));

    final destinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard_rounded),
        label: Text('Dashboard'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          child: const Icon(Icons.verified_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          child: const Icon(Icons.verified_rounded),
        ),
        label: const Text('Verifications'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: openReports > 0,
          label: Text('$openReports'),
          child: const Icon(Icons.flag_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: openReports > 0,
          label: Text('$openReports'),
          child: const Icon(Icons.flag_rounded),
        ),
        label: const Text('Reports'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings_rounded),
        label: Text('Settings'),
      ),
    ];

    final navItems = [
      const CurvedNavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      CurvedNavItem(
        icon: Icons.verified_outlined,
        activeIcon: Icons.verified_rounded,
        label: 'Verify',
        badge: _badge(pending),
      ),
      CurvedNavItem(
        icon: Icons.flag_outlined,
        activeIcon: Icons.flag_rounded,
        label: 'Reports',
        badge: _badge(openReports),
      ),
      const CurvedNavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ];

    return AdminTabScope(
      openTab: _onTabChanged,
      child: Scaffold(
        extendBody: !wide,
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _onTabChanged,
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: AppColors.surface,
                    selectedIconTheme: const IconThemeData(
                      color: AppColors.primary,
                    ),
                    selectedLabelTextStyle: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    unselectedIconTheme: const IconThemeData(
                      color: AppColors.textSecondary,
                    ),
                    destinations: destinations,
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: page,
                    ),
                  ),
                ],
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: page,
              ),
        bottomNavigationBar: wide
            ? null
            : CurvedNavigationBar(
                selectedIndex: _index,
                onTap: _onTabChanged,
                items: navItems,
              ),
      ),
    );
  }
}
