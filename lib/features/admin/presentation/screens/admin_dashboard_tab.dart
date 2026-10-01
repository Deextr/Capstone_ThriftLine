import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../widgets/admin_dashboard_widgets.dart';
import '../widgets/admin_review_widgets.dart';
import 'admin_tab_scope.dart';

class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading
                ? null
                : () => context.read<AdminDashboardController>().load(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<AdminDashboardController>().load(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppConstants.maxContentWidth,
                  ),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      wideNav ? 32 : 112,
                    ),
                    children: [
                      if (controller.errorMessage != null &&
                          controller.hasData) ...[
                        AdminDashboardBanner(message: controller.errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      if (controller.errorMessage != null &&
                          !controller.hasData)
                        AdminErrorState(
                          message: controller.errorMessage!,
                          onRetry: () =>
                              context.read<AdminDashboardController>().load(),
                        )
                      else if (controller.isLoading)
                        AdminDashboardSkeleton(
                          wide: constraints.maxWidth >= 720,
                        )
                      else ...[
                        const _DateFilters(),
                        const SizedBox(height: 20),
                        _OverviewCards(maxWidth: constraints.maxWidth),
                        const SizedBox(height: 28),
                        const _PendingVerifications(),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DateFilters extends StatelessWidget {
  const _DateFilters();

  @override
  Widget build(BuildContext context) {
    final window = context.watch<AdminDashboardController>().window;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final preset in AdminDatePreset.values)
          AdminUnderlineFilter(
            label:
                preset == AdminDatePreset.custom &&
                    window.preset == AdminDatePreset.custom
                ? window.chipLabel
                : adminDatePresetLabel(preset),
            selected: window.preset == preset,
            onTap: () => _select(context, preset),
          ),
      ],
    );
  }

  Future<void> _select(BuildContext context, AdminDatePreset preset) async {
    final controller = context.read<AdminDashboardController>();
    if (preset == AdminDatePreset.custom) {
      final custom = await showAdminCustomRangePicker(
        context,
        initial: controller.window,
      );
      if (custom != null && context.mounted) {
        await controller.setWindow(custom);
      }
      return;
    }
    final next = switch (preset) {
      AdminDatePreset.today => AdminDateWindow.today(),
      AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
      AdminDatePreset.lastMonth => AdminDateWindow.lastMonth(),
      AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
      AdminDatePreset.custom => controller.window,
    };
    await controller.setWindow(next);
  }
}

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<AdminDashboardController>().counts;
    if (counts == null) return const SizedBox.shrink();

    final cards = [
      AdminOverviewCard(
        label: 'Registered users',
        value: counts.registeredInPeriod,
        detail: 'Created in the selected period',
        icon: Icons.people_outline,
      ),
      AdminOverviewCard(
        label: 'Active users',
        value: counts.activeInPeriod,
        detail: 'Last seen in the selected period',
        icon: Icons.person_search_outlined,
      ),
      AdminOverviewCard(
        label: 'Pending verifications',
        value: counts.pendingVerifications,
        detail: counts.pendingVerifications == 0
            ? 'None currently waiting'
            : 'Currently waiting for review',
        icon: Icons.storefront_outlined,
        attention: counts.pendingVerifications > 0,
        onTap: () => AdminTabScope.open(context, AdminTabScope.verifications),
      ),
      AdminOverviewCard(
        label: 'Open reports',
        value: counts.openReports,
        detail: counts.openReports == 0
            ? 'None currently under review'
            : 'Currently under review',
        icon: Icons.flag_outlined,
        attention: counts.openReports > 0,
        onTap: () => AdminTabScope.open(context, AdminTabScope.reports),
      ),
    ];

    return _OverviewGrid(columns: maxWidth >= 720 ? 4 : 2, children: cards);
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(
        i,
        i + columns > children.length ? children.length : i + columns,
      );
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < slice.length; c++) ...[
              if (c > 0) const SizedBox(width: 12),
              Expanded(child: slice[c]),
            ],
            for (var fill = slice.length; fill < columns; fill++) ...[
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }
}

class _PendingVerifications extends StatelessWidget {
  const _PendingVerifications();

  @override
  Widget build(BuildContext context) {
    final items =
        context
            .watch<AdminDashboardController>()
            .snapshot
            ?.pendingVerifications ??
        const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminDashboardSectionHeader(
          title: 'Pending seller verifications',
          actionLabel: 'View all',
          onAction: () =>
              AdminTabScope.open(context, AdminTabScope.verifications),
        ),
        const SizedBox(height: 4),
        Text(
          'Applications currently waiting for review.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const AdminDashboardEmptyLine('No pending verifications.')
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            AdminPendingVerificationCard(
              shopName: items[i].shopName,
              applicantName: items[i].applicantName,
              submittedAt: items[i].submittedAt,
              onReview: () =>
                  _open(context, RouteNames.adminReviewFor(items[i].id)),
            ),
          ],
      ],
    );
  }
}

Future<void> _open(BuildContext context, String route) async {
  await context.push(route);
  if (context.mounted) {
    await context.read<AdminDashboardController>().load();
  }
}
