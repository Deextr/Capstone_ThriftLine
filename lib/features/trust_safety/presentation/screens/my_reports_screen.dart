import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/my_reports_controller.dart';
import '../../data/buyer_report_filters.dart';
import '../../data/report_reasons.dart';
import '../../domain/buyer_report_list_item.dart';
import '../widgets/my_reports_filter_sheet.dart';
import '../widgets/my_reports_list_skeleton.dart';
import '../widgets/my_reports_pagination_bar.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _openFilterSheet(MyReportsController controller) {
    final applied = controller.appliedFilters;
    MyReportsFilterSheet.show(
      context,
      initialType: applied.type,
      initialStatus: applied.status,
      onApply: (type, status) {
        controller.applyFilters(type: type, status: status);
        _scrollListToTop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyReportsController>();
    final initialLoad = controller.isLoading && !controller.hasAnyReports;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Reports'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: initialLoad
            ? const MyReportsListSkeleton()
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<MyReportsController>().load(),
                child: CustomScrollView(
                  controller: _scrollController,
                  key: const PageStorageKey<String>('buyer_my_reports_list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (controller.hasAnyReports)
                      SliverToBoxAdapter(
                        child: _ReportsListHeader(
                          controller: controller,
                          onFilterTap: () => _openFilterSheet(controller),
                        ),
                      ),
                    if (!controller.hasAnyReports)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyReportsState(
                          message: controller.errorMessage,
                        ),
                      )
                    else if (controller.visibleItems.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _NoMatchingReportsState(
                          onClear: controller.resetFilters,
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        sliver: SliverList.separated(
                          itemCount: controller.paginatedVisibleItems.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item =
                                controller.paginatedVisibleItems[index];
                            return _UnifiedReportCard(item: item);
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: MyReportsPaginationBar(
                          onPageChanged: _scrollListToTop,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReportsListHeader extends StatelessWidget {
  const _ReportsListHeader({
    required this.controller,
    required this.onFilterTap,
  });

  final MyReportsController controller;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    final count = controller.activeFilterCount;
    final summary = controller.activeFilterSummary;
    final total = controller.allItems.length;
    final filtered = controller.visibleItems.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _FilterButton(activeCount: count, onTap: onFilterTap),
              if (controller.isFilterActive) ...[
                SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear filters',
                  onPressed: controller.resetFilters,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 8),
          Text(
            summary,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 2),
          Text(
            controller.isFilterActive
                ? '$filtered matching · $total total'
                : '$total report${total == 1 ? '' : 's'}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (controller.showPagination) ...[
            SizedBox(height: 2),
            Text(
              controller.paginationRangeLabel,
              style: AppTypography.caption.copyWith(
                color: AppColors.textHint,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 20,
                color: activeCount > 0
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
              ),
              SizedBox(width: 8),
              Text(
                activeCount > 0 ? 'Filter ($activeCount)' : 'Filter',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: activeCount > 0
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedReportCard extends StatelessWidget {
  const _UnifiedReportCard({required this.item});

  final BuyerReportListItem item;

  @override
  Widget build(BuildContext context) {
    final statusColor = reportStatusColor(item.status);
    final statusLabel = reportStatusLabel(item.status);
    final statusIcon = reportStatusIcon(item.status);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _KindBadge(label: item.kindLabel),
                  const Spacer(),
                  _StatusBadge(
                    label: statusLabel,
                    icon: statusIcon,
                    color: statusColor,
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                item.reasonLabel,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                item.subjectLabel,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _formatSubmitted(item.createdAt),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Details',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final route = item.kind == BuyerReportTypeFilter.lookingFor
        ? RouteNames.myLookingForReportDetailFor(item.id)
        : RouteNames.reportDetailFor(item.id);
    await context.push(route);
    if (context.mounted) {
      await context.read<MyReportsController>().load(showSpinner: false);
    }
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReportsState extends StatelessWidget {
  const _EmptyReportsState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag_outlined, size: 40, color: AppColors.textHint),
          SizedBox(height: 16),
          Text(
            'No reports yet',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            message ??
                'Reports you submit will appear here so you can track their progress.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoMatchingReportsState extends StatelessWidget {
  const _NoMatchingReportsState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_list_off_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          SizedBox(height: 16),
          Text(
            'No matching reports',
            textAlign: TextAlign.center,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters to see more reports.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

String _formatSubmitted(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Submitted ${months[date.month - 1]} ${date.day}';
}
