import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_review_rules.dart';
import 'admin_dashboard_widgets.dart';

class AdminReportCategoryCard extends StatelessWidget {
  const AdminReportCategoryCard({
    super.key,
    required this.kind,
    required this.summary,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final AdminReportKind kind;
  final AdminReportKindSummary summary;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final needsAttention = summary.underReview > 0;
    return Semantics(
      button: true,
      label:
          '${adminReportKindLabel(kind)}, ${summary.total} total, '
          '${summary.underReview} under review',
      child: Material(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          side: BorderSide(
            color: needsAttention
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(icon, size: 22, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            adminReportKindLabel(kind),
                            style: AppTypography.subheading,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adminReportKindHubSubtitle(kind),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: needsAttention
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (loading)
                  const ShimmerBox(width: double.infinity, height: 36, radius: 8)
                else
                  _StatRow(summary: summary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.summary});

  final AdminReportKindSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _MiniStat(label: 'Total', value: summary.total),
        _MiniStat(
          label: 'Review',
          value: summary.underReview,
          highlight: summary.underReview > 0,
        ),
        _MiniStat(label: 'Resolved', value: summary.resolved),
        _MiniStat(label: 'Closed', value: summary.closed),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primaryLight : AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Text(
        '$value $label',
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: highlight ? AppColors.primaryDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class AdminReportStatusOverview extends StatelessWidget {
  const AdminReportStatusOverview({
    super.key,
    required this.summary,
    required this.selected,
    required this.onSelected,
  });

  final AdminReportKindSummary summary;
  final AdminReportListFilter selected;
  final ValueChanged<AdminReportListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatusCardData(
        filter: AdminReportListFilter.all,
        label: 'Total',
        value: summary.total,
        icon: Icons.inbox_outlined,
      ),
      _StatusCardData(
        filter: AdminReportListFilter.underReview,
        label: 'Under review',
        value: summary.underReview,
        icon: Icons.hourglass_top_outlined,
      ),
      _StatusCardData(
        filter: AdminReportListFilter.resolved,
        label: 'Resolved',
        value: summary.resolved,
        icon: Icons.check_circle_outline,
      ),
      _StatusCardData(
        filter: AdminReportListFilter.closed,
        label: 'Closed',
        value: summary.closed,
        icon: Icons.archive_outlined,
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
                          ? _StatusCard(
                              data: cards[i + c],
                              selected: selected == cards[i + c].filter,
                              onTap: () => onSelected(cards[i + c].filter),
                            )
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

class _StatusCardData {
  const _StatusCardData({
    required this.filter,
    required this.label,
    required this.value,
    required this.icon,
  });

  final AdminReportListFilter filter;
  final String label;
  final int value;
  final IconData icon;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _StatusCardData data;
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
                data.icon,
                size: 16,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                '${data.value}',
                style: AppTypography.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                data.label,
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

class AdminReportsListFilters extends StatelessWidget {
  const AdminReportsListFilters({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final read = context.read<AdminReportsController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          hint: 'Search by name, order, or details',
          icon: Icons.search,
          controller: controller.searchController,
          onChanged: read.setSearch,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showSortSheet(context, controller, read),
                icon: const Icon(Icons.sort_rounded, size: 18),
                label: Text(adminReportSortLabel(controller.sort)),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showDateSheet(context, controller, read),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_dateLabel(controller.dateWindow)),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (controller.hasActiveListFilters) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: read.clearListFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            ),
          ),
        ],
      ],
    );
  }

  String _dateLabel(AdminDateWindow? window) {
    if (window == null) return 'Any date';
    if (window.preset != AdminDatePreset.custom) {
      return adminDatePresetLabel(window.preset);
    }
    return window.chipLabel;
  }

  Future<void> _showSortSheet(
    BuildContext context,
    AdminReportsController controller,
    AdminReportsController read,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Sort by', style: AppTypography.subheading),
              ),
              for (final sort in AdminReportSort.values)
                ListTile(
                  title: Text(adminReportSortLabel(sort)),
                  trailing: controller.sort == sort
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    read.setSort(sort);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDateSheet(
    BuildContext context,
    AdminReportsController controller,
    AdminReportsController read,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Date range', style: AppTypography.subheading),
              ),
              ListTile(
                title: const Text('Any date'),
                trailing: controller.dateWindow == null
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  read.setDateWindow(null);
                  Navigator.pop(sheetContext);
                },
              ),
              for (final preset in [
                AdminDatePreset.today,
                AdminDatePreset.last7Days,
                AdminDatePreset.lastMonth,
                AdminDatePreset.lastYear,
              ])
                ListTile(
                  title: Text(adminDatePresetLabel(preset)),
                  trailing: controller.dateWindow?.preset == preset
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    read.setDateWindow(switch (preset) {
                      AdminDatePreset.today => AdminDateWindow.today(),
                      AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
                      AdminDatePreset.lastMonth => AdminDateWindow.lastMonth(),
                      AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
                      AdminDatePreset.custom => AdminDateWindow.last7Days(),
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              ListTile(
                title: const Text('Custom range…'),
                trailing: controller.dateWindow?.preset == AdminDatePreset.custom
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final custom = await showAdminCustomRangePicker(
                    context,
                    initial: controller.dateWindow,
                  );
                  if (custom != null && context.mounted) {
                    read.setDateWindow(custom);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
