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
import '../widgets/community_dispute_review_modal.dart';
import '../widgets/admin_looking_for_queue_cells.dart';
import '../widgets/looking_for_dispute_review_modal.dart';
import '../widgets/order_dispute_review_modal.dart';

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
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRouteCategory());
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminDisputesHubController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _syncRouteCategory() {
    if (!mounted) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == RouteNames.adminReportsAll) {
      context.read<AdminDisputesHubController>().applyCategoryFromRoute('all');
    } else if (path == RouteNames.adminReportsCommunity) {
      context.read<AdminDisputesHubController>().applyCategoryFromRoute(
        'community',
      );
    } else if (path == RouteNames.adminReportsOrders) {
      context.read<AdminDisputesHubController>().applyCategoryFromRoute(
        'order',
      );
    } else if (path == RouteNames.adminReportsLookingFor) {
      context.read<AdminDisputesHubController>().applyCategoryFromRoute(
        'looking_for',
      );
    } else {
      final category = GoRouterState.of(
        context,
      ).uri.queryParameters['category'];
      context.read<AdminDisputesHubController>().applyCategoryFromRoute(
        category,
      );
    }
  }

  Future<void> _openCase(AdminModerationCaseRow row) async {
    final bool? result = switch (row.caseKind) {
      'community_report' => await showCommunityDisputeReviewModal(
        context: context,
        reportId: row.caseId,
      ),
      'order_report' => await showOrderDisputeReviewModal(
        context: context,
        reportId: row.caseId,
      ),
      'looking_for_report' => await showLookingForDisputeReviewModal(
        context: context,
        reportId: row.caseId,
      ),
      _ => await _openLegacyDisputeRoute(row),
    };

    if (result == true && mounted) {
      await context.read<AdminDisputesHubController>().load();
    }
  }

  Future<bool?> _openLegacyDisputeRoute(AdminModerationCaseRow row) async {
    final route = switch (row.source) {
      'delivery_dispute' => RouteNames.adminDisputeDetailFor(row.caseId),
      'looking_for' => RouteNames.adminLookingForReportFor(row.caseId),
      _ when row.caseKind == 'order_report' => RouteNames.adminReportDetailFor(
        row.caseId,
      ),
      _ => RouteNames.adminReportDetailFor(row.caseId),
    };
    await context.push(route);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesHubController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Segmented Tab Navigation for Disputes categories
          DisputeCategorySegmentedNav(
            selectedCategory: controller.category,
            onCategorySelected: (cat) {
              controller.setCategory(cat);
              context.go(RouteNames.adminDisputesForCategory(cat));
            },
          ),
          const SizedBox(height: 16),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
              context.go(RouteNames.adminReportsAll);
            },
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search disputes…',
                width: 280,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              if (controller.isLookingForCategory)
                AdminFilterDropdown<AdminLookingForLifecycleFilter>(
                  value: controller.lfLifecycleFilter,
                  items: AdminLookingForLifecycleFilter.values
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text(adminLookingForLifecycleFilterLabel(f)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) controller.setLfLifecycleFilter(v);
                  },
                )
              else
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
              if (controller.isLookingForCategory)
                AdminFilterDropdown<AdminReportListFilter>(
                  value: controller.statusFilter,
                  items: const [
                    DropdownMenuItem(
                      value: AdminReportListFilter.all,
                      child: Text('All moderation statuses'),
                    ),
                    DropdownMenuItem(
                      value: AdminReportListFilter.underReview,
                      child: Text('Under review'),
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
            minWidth: controller.isLookingForCategory ? 1020 : 840,
            columnFlex: controller.isLookingForCategory
                ? const [4, 2, 2, 2, 2, 2, 1]
                : const [2, 2, 3, 2, 2, 1],
            emptyTitle: 'No disputes found',
            emptyMessage:
                'Try adjusting your search or filters. New disputes and reports appear here when submitted.',
            onResetFilters: controller.hasActiveFilters
                ? controller.resetFilters
                : null,
            onRowTap: [
              for (final row in controller.items) () => _openCase(row),
            ],
            columns: controller.isLookingForCategory
                ? const [
                    'Post',
                    'Reporter',
                    'Reported member',
                    'Dispute',
                    'Post status',
                    'Reported',
                    'Review',
                  ]
                : const [
                    'Case',
                    'Dispute Type',
                    'Reporter',
                    'Date Submitted',
                    'Status',
                    'Action',
                  ],
            rows: controller.isLookingForCategory
                ? [
                    for (final row in controller.items)
                      [
                        AdminLookingForQueuePostCell(row: row),
                        AdminTableCellText(primary: row.actorName),
                        AdminTableCellText(primary: row.subjectName),
                        AdminLookingForDisputeStatusCell(row: row),
                        AdminLookingForPostStatusCell(row: row),
                        AdminTableDateCell(dateTime: row.createdAt),
                        AdminTableLinkAction(
                          label: 'Review',
                          onPressed: () => _openCase(row),
                        ),
                      ],
                  ]
                : [
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
                          primary: adminModerationCaseKindShortLabel(
                            row.caseKind,
                          ),
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

class DisputeCategorySegmentedNav extends StatelessWidget {
  const DisputeCategorySegmentedNav({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final AdminModerationCategory selectedCategory;
  final ValueChanged<AdminModerationCategory> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final cat in AdminModerationCategory.values)
              _CategoryTabItem(
                label: adminModerationCategoryLabel(cat),
                isSelected: selectedCategory == cat,
                onTap: () => onCategorySelected(cat),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTabItem extends StatelessWidget {
  const _CategoryTabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
