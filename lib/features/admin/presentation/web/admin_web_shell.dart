import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_palette_lerp_sync.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../widgets/admin_profile_modal.dart';

const double _kSidebarIconSlotSize = 24;

class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key, required this.child});

  final Widget child;

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _profileModalOpen = false;

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
    if (location.startsWith(RouteNames.adminMarketplaceReports)) {
      return 'Reports';
    }
    if (location.startsWith('/admin/reports/') ||
        location.startsWith(RouteNames.adminDisputes) ||
        location.startsWith('/admin/looking-for-reports')) {
      return 'Disputes';
    }
    if (location.startsWith(RouteNames.adminLogs)) return 'Activity logs';
    if (location.startsWith(RouteNames.adminAdministrators)) {
      return 'Admin accounts';
    }
    if (location.startsWith(RouteNames.adminUsers)) return 'Users';
    if (location.startsWith(RouteNames.adminOrdersTransactions) ||
        location.startsWith(RouteNames.adminOrders) ||
        location.startsWith(RouteNames.adminTransactions)) {
      return 'Orders & transactions';
    }
    if (location.startsWith(RouteNames.adminBiddingViolations)) {
      return 'Bidding violations';
    }
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
        label: 'Bidding violations',
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments_rounded,
        route: RouteNames.adminBiddingViolations,
      ),
      _NavItem(
        label: 'Disputes',
        icon: Icons.gavel_outlined,
        selectedIcon: Icons.gavel_rounded,
        route: RouteNames.adminReportsAll,
        badge: openCases,
      ),
      _NavItem(
        label: 'Reports',
        icon: Icons.assessment_outlined,
        selectedIcon: Icons.assessment_rounded,
        route: RouteNames.adminMarketplaceReports,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().reloadUser();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AuthProvider>().reloadUser();
    }
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

  Future<void> _openProfileSettings({required bool compact}) async {
    if (compact) _scaffoldKey.currentState?.closeDrawer();
    if (_profileModalOpen) return;
    setState(() => _profileModalOpen = true);
    try {
      await showAdminProfileModal(context);
    } finally {
      if (mounted) setState(() => _profileModalOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    AppPalette.current =
        Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    final location = GoRouterState.of(context).uri.path;
    final wide =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final compact =
        MediaQuery.sizeOf(context).width < AppConstants.breakpointTablet;
    final dashboard = context.watch<AdminDashboardController>();
    final pending = dashboard.pendingVerificationCount;
    final openCases = dashboard.openDisputeCount;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final primaryNav = _primaryNavItems(pending, openCases);
    final administrationNav = auth.isSuperAdmin
        ? const [
            _NavItem(
              label: 'Admin accounts',
              icon: Icons.admin_panel_settings_outlined,
              selectedIcon: Icons.admin_panel_settings_rounded,
              route: RouteNames.adminAdministrators,
            ),
            _NavItem(
              label: 'Activity logs',
              icon: Icons.history_outlined,
              selectedIcon: Icons.history_rounded,
              route: RouteNames.adminLogs,
            ),
          ]
        : const <_NavItem>[];

    Widget sidebar({required bool extended}) {
      return Container(
        width: extended ? _sidebarExpandedWidth : _sidebarRailWidth,
        decoration: BoxDecoration(
          color: AppColors.sidebarSurface,
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
            Divider(height: 1, color: AppColors.border),
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
                  if (administrationNav.isNotEmpty) ...[
                    if (extended)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                        child: Text(
                          'Administration',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Divider(height: 16, color: AppColors.border),
                    for (final item in administrationNav)
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
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
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
                selected: _profileModalOpen,
                onTap: () => _openProfileSettings(compact: compact),
              ),
            ),
          ],
        ),
      );
    }

    final shell = Scaffold(
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
                    decoration: BoxDecoration(
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
                              _AdminHeaderActions(
                                user: user,
                                showName: !compact,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: AppPaletteLerpChild(child: widget.child)),
              ],
            ),
          ),
        ],
      ),
    );

    return shell;
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
        SizedBox(width: 10),
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

class _AdminHeaderActions extends StatelessWidget {
  const _AdminHeaderActions({required this.user, required this.showName});

  final AuthUser? user;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'Admin';

    final avatarUrl = user?.avatarUrl ?? '';

    return Row(
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
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(width: 8),
        const _ThemeToggleButton(),
        const SizedBox(width: 8),
        const _SignOutButton(),
      ],
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = theme.isDarkMode;
    final label = isDark ? 'Switch to light mode' : 'Switch to dark mode';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surfaceVariant.withValues(alpha: 0.65),
          shape: CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: theme.toggleTheme,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatefulWidget {
  const _SignOutButton();

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _hovered = false;
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    context.go(RouteNames.adminLogin);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final compact = MediaQuery.sizeOf(context).width < 520;
    final background = _hovered
        ? palette.signOutHover
        : palette.signOutBackground;

    return Tooltip(
      message: 'Sign out',
      child: Semantics(
        button: true,
        label: 'Sign out',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _busy ? null : _signOut,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.signOutBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: palette.signOutForeground,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Sign out',
                        style: AppTypography.caption.copyWith(
                          color: palette.signOutForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
    final inactive = AppColors.textSecondary;
    final color = selected ? AppColors.primary : inactive;

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

    final tile = DecoratedBox(
      decoration: BoxDecoration(
        gradient: selected ? AppGradients.primaryGradientLight : null,
        color: selected
            ? null
            : _hovered
            ? AppColors.surfaceVariant.withValues(alpha: 0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: selected
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
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
                            letterSpacing: selected ? 0 : null,
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
