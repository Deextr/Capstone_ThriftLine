import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_dashboard_widgets.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReportsQueueScreen extends StatelessWidget {
  const AdminReportsQueueScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final bottomPad = embedded && !wideNav ? 112.0 : 32.0;
    final visible = controller.visibleReports;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        automaticallyImplyLeading: !embedded,
        leading: embedded
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading
                ? null
                : () => context.read<AdminReportsController>().load(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<AdminReportsController>().load(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReportsOverview(controller: controller),
                      const SizedBox(height: 16),
                      _CategoryTabs(
                        selected: controller.kind,
                        onSelected: context
                            .read<AdminReportsController>()
                            .setKind,
                      ),
                      const SizedBox(height: 12),
                      ThriftTextField(
                        hint: 'Search reports, people, or orders',
                        icon: Icons.search,
                        controller: controller.searchController,
                        onChanged: context
                            .read<AdminReportsController>()
                            .setSearch,
                      ),
                      const SizedBox(height: 8),
                      AdminDashboardFilterBar<AdminReportListFilter>(
                        values: AdminReportListFilter.values,
                        selected: controller.filter,
                        labelOf: adminReportListFilterLabel,
                        onSelected: context
                            .read<AdminReportsController>()
                            .setFilter,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          AdminUnderlineFilter(
                            label: 'Any date',
                            selected: controller.dateWindow == null,
                            onTap: () => context
                                .read<AdminReportsController>()
                                .setDateWindow(null),
                          ),
                          for (final preset in [
                            AdminDatePreset.today,
                            AdminDatePreset.last7Days,
                            AdminDatePreset.lastMonth,
                            AdminDatePreset.lastYear,
                          ])
                            AdminUnderlineFilter(
                              label: adminDatePresetLabel(preset),
                              selected: controller.dateWindow?.preset == preset,
                              onTap: () => context
                                  .read<AdminReportsController>()
                                  .setDateWindow(switch (preset) {
                                    AdminDatePreset.today =>
                                      AdminDateWindow.today(),
                                    AdminDatePreset.last7Days =>
                                      AdminDateWindow.last7Days(),
                                    AdminDatePreset.lastMonth =>
                                      AdminDateWindow.lastMonth(),
                                    AdminDatePreset.lastYear =>
                                      AdminDateWindow.lastYear(),
                                    AdminDatePreset.custom =>
                                      AdminDateWindow.last7Days(),
                                  }),
                            ),
                          AdminUnderlineFilter(
                            label:
                                controller.dateWindow?.preset ==
                                    AdminDatePreset.custom
                                ? controller.dateWindow!.chipLabel
                                : 'Custom Range',
                            selected:
                                controller.dateWindow?.preset ==
                                AdminDatePreset.custom,
                            onTap: () async {
                              final custom = await showAdminCustomRangePicker(
                                context,
                                initial: controller.dateWindow,
                              );
                              if (custom != null && context.mounted) {
                                context
                                    .read<AdminReportsController>()
                                    .setDateWindow(custom);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AdminDashboardFilterBar<AdminReportSort>(
                        values: AdminReportSort.values,
                        selected: controller.sort,
                        labelOf: adminReportSortLabel,
                        onSelected: context
                            .read<AdminReportsController>()
                            .setSort,
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(const [
                      ShimmerBox(width: 148, height: 14),
                      SizedBox(height: 20),
                      ShimmerBox(
                        width: double.infinity,
                        height: 88,
                        radius: 12,
                      ),
                      SizedBox(height: 10),
                      ShimmerBox(
                        width: double.infinity,
                        height: 88,
                        radius: 12,
                      ),
                      SizedBox(height: 10),
                      ShimmerBox(
                        width: double.infinity,
                        height: 88,
                        radius: 12,
                      ),
                    ]),
                  ),
                )
              else if (controller.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AdminErrorState(
                    message: controller.errorMessage!,
                    onRetry: () =>
                        context.read<AdminReportsController>().load(),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AdminEmptyState(
                    title: _emptyTitle(controller),
                    message: _emptyMessage(controller),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index.isOdd) return const SizedBox(height: 10);
                      final report = visible[index ~/ 2];
                      return AdminReportCard(
                        reportId: report.id,
                        kindLabel: adminReportKindOf(
                          category: report.category,
                          orderId: report.orderId,
                        ),
                        reporterName: adminHandle(
                          report.reporterUsername,
                          report.reporterDisplayName,
                        ),
                        reporterRole: accountRoleLabel(report.reporterRole),
                        reportedName: adminHandle(
                          report.reportedUsername,
                          report.reportedDisplayName,
                        ),
                        reportedRole: accountRoleLabel(report.reportedRole),
                        reason: reportReasonLabel(report.category),
                        preview: adminReportPreview(report.details),
                        status: report.status,
                        statusLabel: reportStatusLabel(report.status),
                        createdAt: report.createdAt,
                        orderNumber: report.orderNumber,
                        onView: () => _open(context, report.id),
                      );
                    }, childCount: visible.length * 2 - 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _emptyTitle(AdminReportsController controller) {
    final inKind = controller.reports.where(controller.matchesKind);
    if (inKind.isEmpty) {
      return switch (controller.kind) {
        AdminReportKind.community => 'No community reports',
        AdminReportKind.order => 'No order reports',
        AdminReportKind.all => 'No reports',
      };
    }
    return 'No matching reports';
  }

  String _emptyMessage(AdminReportsController controller) {
    final inKind = controller.reports.where(controller.matchesKind);
    if (inKind.isEmpty) {
      return switch (controller.kind) {
        AdminReportKind.community =>
          'No community reports have been submitted.',
        AdminReportKind.order =>
          'No order-related reports have been submitted.',
        AdminReportKind.all => 'New reports will appear here.',
      };
    }
    return 'No reports match the selected filters.';
  }
}

class _ReportsOverview extends StatelessWidget {
  const _ReportsOverview({required this.controller});

  final AdminReportsController controller;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _OverviewChip(
        label: 'Total Reports',
        value: controller.totalCount,
        icon: Icons.assignment_outlined,
        selected: controller.filter == AdminReportListFilter.all,
        onTap: () => context.read<AdminReportsController>().setFilter(
          AdminReportListFilter.all,
        ),
      ),
      _OverviewChip(
        label: 'Under Review',
        value: controller.underReviewCount,
        icon: Icons.hourglass_empty_outlined,
        selected: controller.filter == AdminReportListFilter.underReview,
        onTap: () => context.read<AdminReportsController>().setFilter(
          AdminReportListFilter.underReview,
        ),
      ),
      _OverviewChip(
        label: 'Resolved',
        value: controller.resolvedCount,
        icon: Icons.check_circle_outline,
        selected: controller.filter == AdminReportListFilter.resolved,
        onTap: () => context.read<AdminReportsController>().setFilter(
          AdminReportListFilter.resolved,
        ),
      ),
      _OverviewChip(
        label: 'Closed',
        value: controller.closedCount,
        icon: Icons.gavel_outlined,
        selected: controller.filter == AdminReportListFilter.closed,
        onTap: () => context.read<AdminReportsController>().setFilter(
          AdminReportListFilter.closed,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: i + c < cards.length
                          ? cards[i + c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                '$value',
                style: AppTypography.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});

  final AdminReportKind selected;
  final ValueChanged<AdminReportKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final kind in AdminReportKind.values)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: kind == selected
                        ? AppGradients.buttonGradient
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onSelected(kind),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            adminReportKindLabel(kind),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: AppTypography.label.copyWith(
                              color: kind == selected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, String reportId) async {
  await context.push(RouteNames.adminReportDetailFor(reportId));
  if (context.mounted) {
    await context.read<AdminReportsController>().load();
  }
}
