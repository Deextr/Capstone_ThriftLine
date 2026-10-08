import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_review_rules.dart';
import '../../../../models/enums.dart';
import '../widgets/admin_dashboard_widgets.dart';
import '../widgets/admin_review_widgets.dart';
import 'admin_tab_scope.dart';

class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key, this.webEmbedded = false});

  final bool webEmbedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;

    final body = SafeArea(
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
                  padding: EdgeInsets.fromLTRB(20, 20, 20, wideNav ? 32 : 112),
                  children: [
                    if (controller.errorMessage != null &&
                        controller.hasData) ...[
                      AdminDashboardBanner(message: controller.errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    if (controller.errorMessage != null && !controller.hasData)
                      AdminErrorState(
                        message: controller.errorMessage!,
                        onRetry: () =>
                            context.read<AdminDashboardController>().load(),
                      )
                    else if (controller.isLoading)
                      AdminDashboardSkeleton(wide: constraints.maxWidth >= 720)
                    else ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: _DateFilters(),
                      ),
                      const SizedBox(height: 24),
                      _OverviewCards(
                        maxWidth: constraints.maxWidth,
                        webEmbedded: webEmbedded,
                      ),
                      const SizedBox(height: 32),
                      const _MarketplacePerformance(),
                      const SizedBox(height: 32),
                      _SalesChart(maxWidth: constraints.maxWidth),
                      const SizedBox(height: 32),
                      const _OrderOverview(),
                      const SizedBox(height: 32),
                      _NeedsAttention(webEmbedded: webEmbedded),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (webEmbedded) {
      return ColoredBox(
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.isRefreshing)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: AppColors.border,
              ),
            Expanded(child: body),
          ],
        ),
      );
    }

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
      body: body,
    );
  }
}

class _DateFilters extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final window = context.watch<AdminDashboardController>().window;
    return AdminDashboardDateRangeBar(
      window: window,
      onPresetSelected: (preset) => _select(context, preset),
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
      AdminDatePreset.last30Days => AdminDateWindow.last30Days(),
      AdminDatePreset.thisMonth => AdminDateWindow.thisMonth(),
      AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
      AdminDatePreset.custom => controller.window,
    };
    await controller.setWindow(next);
  }
}

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({required this.maxWidth, this.webEmbedded = false});

  final double maxWidth;
  final bool webEmbedded;

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<AdminDashboardController>().counts;
    if (counts == null) return const SizedBox.shrink();

    final cards = [
      AdminOverviewCard(
        label: 'Registered users',
        value: counts.totalUsers,
        detail: 'Total registered accounts',
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
        label: 'Open cases',
        value: counts.openReports + counts.openDisputes,
        detail: counts.openReports + counts.openDisputes == 0
            ? 'No reports or delivery problems waiting'
            : 'Reports and delivery problems under review',
        icon: Icons.gavel_outlined,
        attention: counts.openReports + counts.openDisputes > 0,
        onTap: () {
          if (webEmbedded) {
            context.go(RouteNames.adminReportsAll);
          } else {
            AdminTabScope.open(context, AdminTabScope.reports);
          }
        },
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

class _MarketplacePerformance extends StatelessWidget {
  const _MarketplacePerformance();

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<AdminDashboardController>().counts;
    if (counts == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Marketplace performance', style: AppTypography.subheading),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AdminOverviewCard(
                label: 'Gross marketplace sales',
                value: counts.grossMarketplaceSales.round(),
                displayValue: formatCurrency(counts.grossMarketplaceSales),
                detail: 'Paid sales in the selected period',
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminOverviewCard(
                label: 'Platform revenue',
                value: counts.platformRevenue.round(),
                displayValue: formatCurrency(counts.platformRevenue),
                detail: 'Fees collected in the selected period',
                icon: Icons.account_balance_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<AdminDashboardController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final points = [
      for (var i = 0; i < snapshot.salesRevenueSeries.length; i++)
        AdminDashboardPoint(
          day: snapshot.salesRevenueSeries[i].day,
          count: snapshot.salesRevenueSeries[i].gross.round(),
        ),
    ];
    return AdminTrendChart(
      title: 'Sales & revenue overview',
      points: points,
      emptyMessage: 'No paid marketplace sales in this period.',
    );
  }
}

class _OrderOverview extends StatelessWidget {
  const _OrderOverview();

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<AdminDashboardController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return AdminTrendChart(
      title: 'Order overview',
      points: snapshot.ordersByDay,
      emptyMessage: 'No orders in this period.',
      breakdown: snapshot.ordersByStatus,
      breakdownLabel: (status) => orderStatusLabel(orderStatusFromDb(status)),
    );
  }
}

class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({this.webEmbedded = false});

  final bool webEmbedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final verifications = controller.snapshot?.pendingVerifications ?? const [];
    final reports = controller.visibleReports
        .where((r) => r.status == kAdminReportOpenStatus)
        .take(5)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Needs attention', style: AppTypography.subheading),
        const SizedBox(height: 16),
        AdminDashboardSectionHeader(
          title: 'Pending seller verifications',
          actionLabel: 'View all',
          onAction: () =>
              AdminTabScope.open(context, AdminTabScope.verifications),
        ),
        const SizedBox(height: 8),
        if (verifications.isEmpty)
          const AdminDashboardEmptyLine('No pending seller verifications.')
        else
          for (final item in verifications.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AdminPendingVerificationCard(
                shopName: item.shopName,
                applicantName: item.applicantName,
                submittedAt: item.submittedAt,
                onReview: () =>
                    _open(context, RouteNames.adminReviewFor(item.id)),
              ),
            ),
        const SizedBox(height: 20),
        AdminDashboardSectionHeader(
          title: 'Open reports',
          actionLabel: 'View all',
          onAction: () {
            if (webEmbedded) {
              context.go(RouteNames.adminReportsAll);
            } else {
              AdminTabScope.open(context, AdminTabScope.reports);
            }
          },
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          const AdminDashboardEmptyLine('No open reports for this period.')
        else
          for (final report in reports)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border),
                ),
                title: Text(report.reasonLabel),
                subtitle: Text('${report.reportedName} · ${report.roleLabel}'),
                trailing: TextButton(
                  onPressed: () => _open(
                    context,
                    RouteNames.adminReportDetailFor(report.id),
                  ),
                  child: const Text('Review report'),
                ),
              ),
            ),
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
