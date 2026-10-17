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
import '../../../../core/services/shared_preferences_service.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../widgets/admin_profile_modal.dart';
import '../widgets/admin_sign_out_dialog.dart';
import '../widgets/admin_theme_toggle_button.dart';
import 'admin_sidebar_nav.dart';

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
  bool _sidebarExpanded = true;
  bool _sidebarRevealLabels = true;
  bool _sidebarPrefsLoaded = false;
  final Set<String> _sectionsExpandedByUser = {};
  final Set<String> _sectionsCollapsedByUser = {};

  static const Duration _sidebarAnimDuration = Duration(milliseconds: 220);
  static const double _sidebarExpandedWidth = 252;
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
    if (location.startsWith(RouteNames.adminSellerPayouts)) {
      return 'Seller payouts';
    }
    if (location.startsWith(RouteNames.adminBuyerRefunds)) {
      return 'Buyer refunds';
    }
    return 'ThriftLine Admin';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sidebarPrefsLoaded) return;
    _sidebarPrefsLoaded = true;
    _sidebarExpanded = context
        .read<SharedPreferencesService>()
        .adminSidebarExpanded;
    _sidebarRevealLabels = _sidebarExpanded;
  }

  Future<void> _setSidebarExpanded(bool expanded) async {
    if (_sidebarExpanded == expanded) return;
    final prefs = context.read<SharedPreferencesService>();
    if (expanded) {
      setState(() {
        _sidebarExpanded = true;
        _sidebarRevealLabels = false;
      });
      await Future<void>.delayed(_sidebarAnimDuration);
      if (mounted) setState(() => _sidebarRevealLabels = true);
    } else {
      setState(() {
        _sidebarRevealLabels = false;
        _sidebarExpanded = false;
      });
    }
    await prefs.setAdminSidebarExpanded(expanded);
  }

  bool _sectionIsExpanded(AdminNavSection section, String location) {
    if (section.items.length <= 1) return true;
    if (_sectionsCollapsedByUser.contains(section.title)) return false;
    if (_sectionsExpandedByUser.contains(section.title)) return true;
    return adminSectionHasSelectedItem(location, section);
  }

  void _toggleSectionExpanded(AdminNavSection section, String location) {
    final expanded = _sectionIsExpanded(section, location);
    setState(() {
      if (expanded) {
        _sectionsExpandedByUser.remove(section.title);
        _sectionsCollapsedByUser.add(section.title);
      } else {
        _sectionsCollapsedByUser.remove(section.title);
        _sectionsExpandedByUser.add(section.title);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AuthProvider>().reloadUser();
    }
  }

  static const _settingsNav = AdminNavItem(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    route: RouteNames.adminSettings,
  );

  void _navigate(
    String route, {
    required bool compact,
    String? expandSectionTitle,
  }) {
    if (expandSectionTitle != null) {
      _sectionsCollapsedByUser.remove(expandSectionTitle);
    }
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
    final compact =
        MediaQuery.sizeOf(context).width < AppConstants.breakpointTablet;
    final sidebarWidthExpanded = compact || _sidebarExpanded;
    final sidebarContentExtended =
        compact || (_sidebarExpanded && _sidebarRevealLabels);
    final dashboard = context.watch<AdminDashboardController>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final navSections = buildAdminSidebarSections(
      isSuperAdmin: auth.isSuperAdmin,
      pendingVerifications: dashboard.pendingVerificationCount,
      openDisputes: dashboard.openDisputeCount,
      pendingPayouts: dashboard.pendingPayoutCount,
      pendingBuyerRefunds: dashboard.pendingBuyerRefundCount,
    );

    Widget sidebar({
      required bool widthExpanded,
      required bool contentExtended,
    }) {
      return ClipRect(
        child: AnimatedContainer(
          duration: _sidebarAnimDuration,
          curve: Curves.easeInOutCubic,
          width: widthExpanded ? _sidebarExpandedWidth : _sidebarRailWidth,
          decoration: BoxDecoration(
            color: AppColors.sidebarSurface,
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _headerHeight,
                child: ClipRect(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: contentExtended ? _navHorizontalInset : 0,
                    ),
                    child: _SidebarBrand(extended: contentExtended),
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView(
                  clipBehavior: Clip.hardEdge,
                  padding: const EdgeInsets.fromLTRB(
                    _navHorizontalInset,
                    10,
                    _navHorizontalInset,
                    8,
                  ),
                  children: [
                    for (var i = 0; i < navSections.length; i++) ...[
                      if (i > 0 && !contentExtended)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: AppColors.border.withValues(alpha: 0.85),
                          ),
                        ),
                      if (navSections[i].items.length == 1)
                        Padding(
                          padding: EdgeInsets.only(
                            top: i == 0 ? 0 : 6,
                            bottom: 4,
                          ),
                          child: _SidebarTile(
                            item: navSections[i].items.first,
                            extended: contentExtended,
                            selected: adminNavItemSelected(
                              location,
                              navSections[i].items.first.route,
                            ),
                            onTap: () => _navigate(
                              navSections[i].items.first.route,
                              compact: compact,
                            ),
                          ),
                        )
                      else if (contentExtended)
                        _SidebarDropdownSection(
                          section: navSections[i],
                          expanded: _sectionIsExpanded(
                            navSections[i],
                            location,
                          ),
                          location: location,
                          isFirst: i == 0,
                          onToggle: () =>
                              _toggleSectionExpanded(navSections[i], location),
                          onNavigate: (route) => _navigate(
                            route,
                            compact: compact,
                            expandSectionTitle: navSections[i].title,
                          ),
                        )
                      else
                        _SidebarRailDropdownSection(
                          section: navSections[i],
                          location: location,
                          onNavigate: (route) => _navigate(
                            route,
                            compact: compact,
                            expandSectionTitle: navSections[i].title,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _navHorizontalInset,
                    4,
                    _navHorizontalInset,
                    4,
                  ),
                  child: _SidebarWidthToggle(
                    expanded: _sidebarExpanded,
                    showLabel: contentExtended,
                    onPressed: () => _setSidebarExpanded(!_sidebarExpanded),
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
                  extended: contentExtended,
                  selected: _profileModalOpen,
                  onTap: () => _openProfileSettings(compact: compact),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final shell = Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: sidebar(widthExpanded: true, contentExtended: true),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            sidebar(
              widthExpanded: sidebarWidthExpanded,
              contentExtended: sidebarContentExtended,
            ),
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

class _SidebarDropdownSection extends StatefulWidget {
  const _SidebarDropdownSection({
    required this.section,
    required this.expanded,
    required this.location,
    required this.isFirst,
    required this.onToggle,
    required this.onNavigate,
  });

  final AdminNavSection section;
  final bool expanded;
  final String location;
  final bool isFirst;
  final VoidCallback onToggle;
  final ValueChanged<String> onNavigate;

  @override
  State<_SidebarDropdownSection> createState() =>
      _SidebarDropdownSectionState();
}

class _SidebarDropdownSectionState extends State<_SidebarDropdownSection> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final sectionActive = adminSectionHasSelectedItem(widget.location, section);
    final badgeTotal = adminSectionBadgeTotal(section);
    final headerColor = sectionActive
        ? AppColors.primary
        : AppColors.textSecondary;

    Widget headerIcon() {
      return SizedBox(
        width: _kSidebarIconSlotSize,
        height: _kSidebarIconSlotSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              sectionActive ? section.selectedIcon : section.icon,
              size: 22,
              color: headerColor,
            ),
            if (badgeTotal > 0 && !widget.expanded)
              Positioned(
                top: -4,
                right: -6,
                child: _SidebarBadge(count: badgeTotal),
              ),
          ],
        ),
      );
    }

    final header = DecoratedBox(
      decoration: BoxDecoration(
        color: sectionActive
            ? AppColors.primary.withValues(alpha: 0.08)
            : _hovered
            ? AppColors.surfaceVariant.withValues(alpha: 0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: sectionActive && !widget.expanded
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.25))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onToggle,
          onHover: (hover) => setState(() => _hovered = hover),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                headerIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
                    style: AppTypography.body.copyWith(
                      color: sectionActive
                          ? AppColors.textPrimary
                          : AppColors.textPrimary.withValues(alpha: 0.92),
                      fontWeight: sectionActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badgeTotal > 0 && widget.expanded)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _SidebarBadge(count: badgeTotal),
                  ),
                AnimatedRotation(
                  turns: widget.expanded ? 0.5 : 0,
                  duration: _AdminWebShellState._sidebarAnimDuration,
                  curve: Curves.easeInOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: widget.isFirst ? 0 : 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: widget.expanded,
            label: section.title,
            child: header,
          ),
          AnimatedSize(
            duration: _AdminWebShellState._sidebarAnimDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: widget.expanded
                ? Padding(
                    padding: const EdgeInsets.only(left: 14, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in section.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: _SidebarTile(
                              item: item,
                              extended: true,
                              nested: true,
                              selected: adminNavItemSelected(
                                widget.location,
                                item.route,
                              ),
                              onTap: () => widget.onNavigate(item.route),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SidebarRailDropdownSection extends StatefulWidget {
  const _SidebarRailDropdownSection({
    required this.section,
    required this.location,
    required this.onNavigate,
  });

  final AdminNavSection section;
  final String location;
  final ValueChanged<String> onNavigate;

  @override
  State<_SidebarRailDropdownSection> createState() =>
      _SidebarRailDropdownSectionState();
}

class _SidebarRailDropdownSectionState
    extends State<_SidebarRailDropdownSection> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _hovered = false;

  Future<void> _openMenu() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    final route = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width + 4,
        offset.dy,
        offset.dx + size.width + 280,
        offset.dy + 320,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      elevation: 8,
      items: [
        for (final item in widget.section.items)
          PopupMenuItem<String>(
            value: item.route,
            height: 44,
            child: Row(
              children: [
                Icon(
                  adminNavItemSelected(widget.location, item.route)
                      ? item.selectedIcon
                      : item.icon,
                  size: 20,
                  color: adminNavItemSelected(widget.location, item.route)
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppTypography.body.copyWith(
                      fontWeight:
                          adminNavItemSelected(widget.location, item.route)
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (item.badge > 0) _SidebarBadge(count: item.badge),
              ],
            ),
          ),
      ],
    );

    if (route != null && mounted) widget.onNavigate(route);
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final sectionActive = adminSectionHasSelectedItem(widget.location, section);
    final badgeTotal = adminSectionBadgeTotal(section);
    final color = sectionActive ? AppColors.primary : AppColors.textSecondary;

    final tile = DecoratedBox(
      key: _anchorKey,
      decoration: BoxDecoration(
        gradient: sectionActive ? AppGradients.primaryGradientLight : null,
        color: sectionActive
            ? null
            : _hovered
            ? AppColors.surfaceVariant.withValues(alpha: 0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: sectionActive
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openMenu,
          onHover: (hover) => setState(() => _hovered = hover),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: _kSidebarIconSlotSize,
                height: _kSidebarIconSlotSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      sectionActive ? section.selectedIcon : section.icon,
                      size: 22,
                      color: color,
                    ),
                    if (badgeTotal > 0)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: _SidebarBadge(count: badgeTotal),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: section.title,
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(button: true, label: section.title, child: tile),
      ),
    );
  }
}

class _SidebarBadge extends StatelessWidget {
  const _SidebarBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
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
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        logoPath,
        width: extended ? 28 : 32,
        height: extended ? 28 : 32,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.storefront_outlined,
          color: AppColors.primary,
          size: extended ? 24 : 28,
        ),
      ),
    );

    if (!extended) {
      return Center(child: logo);
    }

    return Row(
      children: [
        logo,
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

class _SidebarWidthToggle extends StatefulWidget {
  const _SidebarWidthToggle({
    required this.expanded,
    required this.showLabel,
    required this.onPressed,
  });

  final bool expanded;
  final bool showLabel;
  final VoidCallback onPressed;

  @override
  State<_SidebarWidthToggle> createState() => _SidebarWidthToggleState();
}

class _SidebarWidthToggleState extends State<_SidebarWidthToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.expanded ? 'Collapse sidebar' : 'Expand sidebar';
    final icon = widget.expanded
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: _hovered
                ? AppColors.surfaceVariant.withValues(alpha: 0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.showLabel ? 10 : 0,
                  vertical: 8,
                ),
                child: widget.showLabel
                    ? Row(
                        children: [
                          Icon(icon, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          icon,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
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
        const AdminThemeToggleButton(),
        const SizedBox(width: 8),
        const _SignOutButton(),
      ],
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
    try {
      await confirmAdminSignOut(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.extended,
    required this.selected,
    required this.onTap,
    this.nested = false,
  });

  final AdminNavItem item;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;
  final bool nested;

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
              size: widget.nested ? 20 : 22,
              color: color,
            ),
            if (widget.item.badge > 0)
              Positioned(
                top: -4,
                right: -6,
                child: _SidebarBadge(count: widget.item.badge),
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
              horizontal: widget.extended ? (widget.nested ? 8 : 10) : 0,
              vertical: widget.nested ? 8 : 10,
            ),
            child: widget.extended
                ? Row(
                    children: [
                      iconSlot(),
                      SizedBox(width: widget.nested ? 10 : 12),
                      Expanded(
                        child: Text(
                          widget.item.label,
                          style:
                              (widget.nested
                                      ? AppTypography.caption
                                      : AppTypography.body)
                                  .copyWith(
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
