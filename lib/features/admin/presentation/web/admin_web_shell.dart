import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../controllers/admin_dashboard_controller.dart';

class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key, required this.child});

  final Widget child;

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _titleForLocation(String location) {
    if (location.startsWith(RouteNames.adminDashboard) ||
        location == RouteNames.adminHome) {
      return 'Dashboard';
    }
    if (location.startsWith('/admin/verifications') ||
        location.startsWith('/admin/applications') ||
        location.startsWith('/admin/review/')) {
      return 'Seller verifications';
    }
    if (location.contains('/admin/reports')) return 'Reports';
    if (location.startsWith(RouteNames.adminLogs)) return 'Logs';
    if (location.startsWith(RouteNames.adminUsers)) return 'Users';
    if (location.startsWith(RouteNames.adminOrders)) return 'Orders';
    if (location.startsWith(RouteNames.adminTransactions)) {
      return 'Transactions';
    }
    if (location.startsWith(RouteNames.adminDisputes)) return 'Disputes';
    if (location.startsWith(RouteNames.adminSettings)) return 'Settings';
    return 'ThriftLine Admin';
  }

  bool _isSelected(String location, String target) {
    if (target == RouteNames.adminDashboard) {
      return location == RouteNames.adminDashboard ||
          location == RouteNames.adminHome;
    }
    return location.startsWith(target);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final compact =
        MediaQuery.sizeOf(context).width < AppConstants.breakpointTablet;
    final pending =
        context.watch<AdminDashboardController>().counts?.pendingVerifications ??
        0;
    final openReports =
        context.watch<AdminDashboardController>().counts?.openReports ?? 0;
    final user = context.watch<AuthProvider>().user;

    final navItems = [
      _NavItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        route: RouteNames.adminDashboard,
      ),
      _NavItem(
        label: 'Verifications',
        icon: Icons.verified_outlined,
        selectedIcon: Icons.verified_rounded,
        route: RouteNames.adminVerifications,
        badge: pending,
      ),
      _NavItem(
        label: 'Reports',
        icon: Icons.flag_outlined,
        selectedIcon: Icons.flag_rounded,
        route: RouteNames.adminReports,
        badge: openReports,
      ),
      _NavItem(
        label: 'Logs',
        icon: Icons.history_outlined,
        selectedIcon: Icons.history_rounded,
        route: RouteNames.adminLogs,
      ),
      _NavItem(
        label: 'Users',
        icon: Icons.people_outline,
        selectedIcon: Icons.people_rounded,
        route: RouteNames.adminUsers,
      ),
      _NavItem(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        route: RouteNames.adminOrders,
      ),
      _NavItem(
        label: 'Transactions',
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments_rounded,
        route: RouteNames.adminTransactions,
      ),
      _NavItem(
        label: 'Disputes',
        icon: Icons.gavel_outlined,
        selectedIcon: Icons.gavel_rounded,
        route: RouteNames.adminDisputes,
      ),
      _NavItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        route: RouteNames.adminSettings,
      ),
    ];

    Widget sidebar({required bool extended}) {
      return Container(
        width: extended ? 240 : 72,
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? 20 : 12, 20, 12, 16),
              child: extended
                  ? Text(
                      'ThriftLine Admin',
                      style: AppTypography.subheading.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(Icons.storefront_outlined, color: AppColors.primary),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final item in navItems)
                    _SidebarTile(
                      item: item,
                      extended: extended,
                      selected: _isSelected(location, item.route),
                      onTap: () {
                        if (compact) _scaffoldKey.currentState?.closeDrawer();
                        context.go(item.route);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: compact
          ? Drawer(child: SafeArea(child: sidebar(extended: true)))
          : null,
      body: Row(
        children: [
          if (!compact) sidebar(extended: wide),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: AppColors.surface,
                  elevation: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              if (compact)
                                IconButton(
                                  icon: const Icon(Icons.menu),
                                  onPressed: () =>
                                      _scaffoldKey.currentState?.openDrawer(),
                                ),
                              Text(
                                _titleForLocation(location),
                                style: AppTypography.subheading.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Refresh dashboard counts',
                                icon: const Icon(Icons.refresh),
                                onPressed: () =>
                                    context.read<AdminDashboardController>().load(),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Admin profile',
                                offset: const Offset(0, 40),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        child: Text(
                                          (user?.name.isNotEmpty == true
                                                  ? user!.name[0]
                                                  : 'A')
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (wide) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          user?.name ?? 'Admin',
                                          style: AppTypography.caption.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Icon(Icons.expand_more, size: 18),
                                      ],
                                    ],
                                  ),
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    enabled: false,
                                    child: Text('Administrator'),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'settings',
                                    child: const Text('Settings'),
                                    onTap: () =>
                                        context.go(RouteNames.adminSettings),
                                  ),
                                  PopupMenuItem(
                                    value: 'logout',
                                    child: const Text('Sign out'),
                                    onTap: () async {
                                      await context.read<AuthProvider>().logout();
                                      if (context.mounted) {
                                        context.go(RouteNames.adminLogin);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
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

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.extended,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    final icon = Badge(
      isLabelVisible: item.badge > 0,
      label: Text('${item.badge}'),
      child: Icon(selected ? item.selectedIcon : item.icon, color: color),
    );
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 16 : 12,
            vertical: 12,
          ),
          child: extended
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: AppTypography.body.copyWith(
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: icon),
        ),
      ),
    );
  }
}
