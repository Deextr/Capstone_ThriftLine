import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/admin_disputes_hub_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_moderation_queue_service.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebDisputesPage extends StatefulWidget {
  const AdminWebDisputesPage({super.key});

  @override
  State<AdminWebDisputesPage> createState() => _AdminWebDisputesPageState();
}

class _AdminWebDisputesPageState extends State<AdminWebDisputesPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRouteCategory());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _syncRouteCategory() {
    if (!mounted) return;
    final category = GoRouterState.of(context).uri.queryParameters['category'];
    context.read<AdminDisputesHubController>().applyCategoryFromRoute(category);
  }

  Future<void> _openCase(AdminModerationCaseRow row) async {
    final route = switch (row.source) {
      'looking_for' => RouteNames.adminLookingForReportFor(row.caseId),
      _ => RouteNames.adminReportDetailFor(row.caseId),
    };
    await context.push(route);
    if (mounted) {
      await context.read<AdminDisputesHubController>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesHubController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in AdminModerationCategory.values)
                _CategoryChip(
                  label: adminModerationCategoryLabel(cat),
                  selected: controller.category == cat,
                  onTap: () {
                    controller.setCategory(cat);
                    context.go(switch (cat) {
                      AdminModerationCategory.community =>
                        RouteNames.adminReportsCommunity,
                      AdminModerationCategory.order =>
                        RouteNames.adminReportsOrders,
                      AdminModerationCategory.lookingFor =>
                        RouteNames.adminReportsLookingFor,
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
              context.go(RouteNames.adminReportsCommunity);
            },
            trailing: OutlinedButton.icon(
              onPressed: controller.isLoading ? null : () => controller.load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search disputes…',
                width: 280,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<AdminReportListFilter>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(
                    value: AdminReportListFilter.all,
                    child: Text('All statuses'),
                  ),
                  DropdownMenuItem(
                    value: AdminReportListFilter.underReview,
                    child: Text('Under review'),
                  ),
                  DropdownMenuItem(
                    value: AdminReportListFilter.needsMoreEvidence,
                    child: Text('Needs more evidence'),
                  ),
                  DropdownMenuItem(
                    value: AdminReportListFilter.resolved,
                    child: Text('Resolved'),
                  ),
                  DropdownMenuItem(
                    value: AdminReportListFilter.dismissed,
                    child: Text('Dismissed'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) controller.setStatusFilter(v);
                },
              ),
              AdminFilterDropdown<AdminDatePreset?>(
                value: controller.dateWindow?.preset,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All time')),
                  DropdownMenuItem(
                    value: AdminDatePreset.today,
                    child: Text('Today'),
                  ),
                  DropdownMenuItem(
                    value: AdminDatePreset.last7Days,
                    child: Text('Last 7 days'),
                  ),
                  DropdownMenuItem(
                    value: AdminDatePreset.last30Days,
                    child: Text('Last 30 days'),
                  ),
                ],
                onChanged: (preset) {
                  if (preset == null) {
                    controller.setDateWindow(null);
                    return;
                  }
                  final window = switch (preset) {
                    AdminDatePreset.today => AdminDateWindow.today(),
                    AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
                    AdminDatePreset.last30Days => AdminDateWindow.last30Days(),
                    AdminDatePreset.thisMonth => AdminDateWindow.thisMonth(),
                    AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
                    AdminDatePreset.custom => AdminDateWindow.last30Days(),
                  };
                  controller.setDateWindow(window);
                },
              ),
            ],
          ),
          if (controller.errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.errorMessage!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
          AdminDataTable(
            isLoading: controller.isLoading,
            minWidth: 820,
            columnFlex: const [2, 2, 3, 2, 2, 1],
            emptyTitle: 'No disputes found',
            emptyMessage:
                'Try adjusting your search or filters. New reports and delivery problems appear here when submitted.',
            onResetFilters: controller.hasActiveFilters
                ? controller.resetFilters
                : null,
            onRowTap: [
              for (final row in controller.items) () => _openCase(row),
            ],
            columns: const [
              'Case',
              'Type',
              'Reported by',
              'Submitted',
              'Status',
              'Action',
            ],
            rows: [
              for (final row in controller.items)
                [
                  AdminTableCellText(
                    primary: adminModerationCaseRef(row.caseId),
                    primaryStyle: AppTypography.tableBody.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  AdminTableCellText(
                    primary: adminModerationCaseKindShortLabel(row.caseKind),
                    primaryStyle: AppTypography.tableBody.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  AdminTableCellText(primary: row.actorName),
                  AdminTableDateCell(dateTime: row.createdAt),
                  AdminStatusBadge(
                    status: row.statusRaw,
                    label: adminModerationStatusLabel(
                      source: row.source,
                      statusRaw: row.statusRaw,
                    ),
                  ),
                  AdminTableLinkAction(
                    label: 'Review',
                    onPressed: () => _openCase(row),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 16),
          AdminPagination(
            currentPage: controller.page,
            totalItems: controller.total,
            pageSize: controller.pageSize,
            isLoading: controller.isLoading,
            pageSizeOptions: const [10, 25, 50],
            onPageChanged: controller.setPage,
            onPageSizeChanged: controller.setPageSize,
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
