import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_dashboard_controller.dart';

const double _kSidebarIconSlotSize = 24;

class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key, required this.child});

  final Widget child;

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const double _sidebarExpandedWidth = 240;
  static const double _sidebarRailWidth = 72;
  static const double _headerHeight = 60;
  static const double _navHorizontalInset = 12;
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
    if (location == RouteNames.adminReports) return 'Analytics';
    if (location.startsWith('/admin/reports/') ||
        location.startsWith(RouteNames.adminDisputes) ||
        location.startsWith('/admin/looking-for-reports')) {
      return 'Disputes';
    }
    if (location.startsWith(RouteNames.adminLogs)) return 'Logs';
    if (location.startsWith(RouteNames.adminUsers)) return 'Users';
    if (location.startsWith(RouteNames.adminOrdersTransactions) ||
        location.startsWith(RouteNames.adminOrders) ||
        location.startsWith(RouteNames.adminTransactions)) {
      return 'Orders & transactions';
    }
    if (location.startsWith(RouteNames.adminSettings)) return 'Settings';
    if (location.startsWith(RouteNames.adminProfile)) return 'Profile';
    return 'ThriftLine Admin';
  }

  bool _isSelected(String location, String target) {
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
    if (target == RouteNames.adminReportsAll ||
        target == RouteNames.adminReportsCommunity) {
      return (location.startsWith('/admin/reports/') &&
              location != RouteNames.adminReports) ||
          location.startsWith(RouteNames.adminDisputes) ||
          location.startsWith('/admin/looking-for-reports');
    }
    return location.startsWith(target);
  }

  List<_NavItem> _primaryNavItems(int pending, int openCases) {
    return [
      _NavItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        route: RouteNames.adminDashboard,
      ),
      _NavItem(
        label: 'Seller verifications',
        icon: Icons.verified_outlined,
        selectedIcon: Icons.verified_rounded,
        route: RouteNames.adminVerifications,
        badge: pending,
      ),
      _NavItem(
        label: 'Users',
        icon: Icons.people_outline,
        selectedIcon: Icons.people_rounded,
        route: RouteNames.adminUsers,
      ),
      _NavItem(
        label: 'Orders & transactions',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        route: RouteNames.adminOrdersTransactions,
      ),
      _NavItem(
        label: 'Logs',
        icon: Icons.history_outlined,
        selectedIcon: Icons.history_rounded,
        route: RouteNames.adminLogs,
      ),
      _NavItem(
        label: 'Disputes',
        icon: Icons.gavel_outlined,
        selectedIcon: Icons.gavel_rounded,
        route: RouteNames.adminReportsAll,
        badge: openCases,
      ),
    ];
  }

  static const _settingsNav = _NavItem(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    route: RouteNames.adminSettings,
  );

  void _navigate(String route, {required bool compact}) {
    if (compact) _scaffoldKey.currentState?.closeDrawer();
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final wide =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final compact =
        MediaQuery.sizeOf(context).width < AppConstants.breakpointTablet;
    final pending =
        context
            .watch<AdminDashboardController>()
            .counts
            ?.pendingVerifications ??
        0;
    final counts = context.watch<AdminDashboardController>().counts;
    final openCases = (counts?.openReports ?? 0) + (counts?.openDisputes ?? 0);
    final user = context.watch<AuthProvider>().user;
    final primaryNav = _primaryNavItems(pending, openCases);

    Widget sidebar({required bool extended}) {
      return Container(
        width: extended ? _sidebarExpandedWidth : _sidebarRailWidth,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _headerHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? _navHorizontalInset : 0,
                ),
                child: _SidebarBrand(extended: extended),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  _navHorizontalInset,
                  8,
                  _navHorizontalInset,
                  8,
                ),
                children: [
                  for (final item in primaryNav)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarTile(
                        item: item,
                        extended: extended,
                        selected: _isSelected(location, item.route),
                        onTap: () => _navigate(item.route, compact: compact),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _navHorizontalInset,
                8,
                _navHorizontalInset,
                12,
              ),
              child: _SidebarTile(
                item: _settingsNav,
                extended: extended,
                selected: _isSelected(location, _settingsNav.route),
                onTap: () => _navigate(_settingsNav.route, compact: compact),
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
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: _headerHeight,
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
                              Expanded(
                                child: Text(
                                  _titleForLocation(location),
                                  style: AppTypography.subheading.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _AdminProfileMenu(user: user, showName: wide),
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

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    const logoPath = 'assets/images/thriftline-logo.png';
    if (!extended) {
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            logoPath,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              Icons.storefront_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
        ),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            logoPath,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              Icons.storefront_outlined,
              color: AppColors.primary,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'ThriftLine Admin',
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AdminProfileMenu extends StatelessWidget {
  const _AdminProfileMenu({required this.user, required this.showName});

  final AuthUser? user;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'Admin';
    final email = user?.email.trim() ?? '';
    final avatarUrl = user?.avatarUrl.trim() ?? '';

    return PopupMenuButton<String>(
      tooltip: 'Admin profile',
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      onSelected: (value) async {
        if (value == 'profile') {
          context.go(RouteNames.adminProfile);
        } else if (value == 'logout') {
          await context.read<AuthProvider>().logout();
          if (context.mounted) {
            context.go(RouteNames.adminLogin);
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 72,
          child: Row(
            children: [
              ThriftAvatar(imageUrl: avatarUrl, name: name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'profile', child: Text('Profile')),
        const PopupMenuItem<String>(value: 'logout', child: Text('Sign out')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThriftAvatar(imageUrl: avatarUrl, name: name, size: 32),
            if (showName) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  name,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more, size: 18),
            ],
          ],
        ),
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

class _SidebarTile extends StatefulWidget {
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
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    final background = selected
        ? AppColors.primary.withValues(alpha: 0.1)
        : _hovered
        ? AppColors.surfaceVariant
        : Colors.transparent;

    Widget iconSlot() {
      return SizedBox(
        width: _kSidebarIconSlotSize,
        height: _kSidebarIconSlotSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              selected ? widget.item.selectedIcon : widget.item.icon,
              size: 22,
              color: color,
            ),
            if (widget.item.badge > 0)
              Positioned(
                top: -4,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.item.badge > 99 ? '99+' : '${widget.item.badge}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final tile = Material(
      color: background,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hover) => setState(() => _hovered = hover),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.extended ? 10 : 0,
            vertical: 10,
          ),
          child: widget.extended
              ? Row(
                  children: [
                    iconSlot(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        style: AppTypography.body.copyWith(
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Center(child: iconSlot()),
        ),
      ),
    );

    if (widget.extended) {
      return Semantics(
        button: true,
        selected: selected,
        label: widget.item.label,
        child: tile,
      );
    }

    return Tooltip(
      message: widget.item.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.item.label,
        child: tile,
      ),
    );
  }
}
