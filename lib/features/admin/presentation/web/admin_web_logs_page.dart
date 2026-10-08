import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_audit_logs_controller.dart';
import '../../data/admin_audit_log_models.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebLogsPage extends StatefulWidget {
  const AdminWebLogsPage({super.key});

  @override
  State<AdminWebLogsPage> createState() => _AdminWebLogsPageState();
}

class _AdminWebLogsPageState extends State<AdminWebLogsPage> {
  final _searchController = TextEditingController();

  void _openDetail(
    BuildContext context,
    AdminAuditLogsController controller,
    AdminAuditLogRow row,
  ) {
    controller.select(row);
    if (MediaQuery.sizeOf(context).width >= 960) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _DetailPanel(row: row, onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminAuditLogsController>();
    final selected = controller.selected;

    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                AdminPageHeader(
                  title: 'Audit Logs',
                  subtitle:
                      'Monitor platform security events, administrative actions, and system activity.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: controller.isLoading
                          ? null
                          : () => controller.load(),
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
                  ],
                ),
                AdminFilterBar(
                  hasActiveFilters: controller.hasActiveFilters,
                  onReset: () {
                    _searchController.clear();
                    controller.resetFilters();
                  },
                  children: [
                    AdminSearchField(
                      controller: _searchController,
                      hintText: 'Search audit logs...',
                      width: 260,
                      onSubmitted: controller.setSearch,
                      onClear: () => controller.setSearch(''),
                    ),
                    AdminFilterDropdown<String>(
                      value: controller.category,
                      items: [
                        for (final opt in AdminAuditCategory.filterOptions)
                          DropdownMenuItem(
                            value: opt.value,
                            child: Text(opt.label),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) controller.setCategory(v);
                      },
                    ),
                    AdminFilterDropdown<String>(
                      value: controller.status,
                      items: const [
                        DropdownMenuItem(
                          value: AdminAuditStatusFilter.all,
                          child: Text('All statuses'),
                        ),
                        DropdownMenuItem(
                          value: AdminAuditStatusFilter.success,
                          child: Text('Success'),
                        ),
                        DropdownMenuItem(
                          value: AdminAuditStatusFilter.failed,
                          child: Text('Failed'),
                        ),
                        DropdownMenuItem(
                          value: AdminAuditStatusFilter.blocked,
                          child: Text('Blocked'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) controller.setStatus(v);
                      },
                    ),
                    AdminDateFilter(
                      window: controller.window,
                      onChanged: controller.setWindow,
                    ),
                  ],
                ),
                if (controller.errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                  columnFlex: const [2, 4, 2, 1],
                  onRowTap: [
                    for (final row in controller.rows)
                      () => _openDetail(context, controller, row),
                  ],
                  emptyTitle: 'No audit logs found',
                  emptyMessage: controller.hasActiveFilters
                      ? 'No audit events match your filters. Try clearing some filters.'
                      : 'Audit logs will appear here as system events occur.',
                  onResetFilters: controller.hasActiveFilters
                      ? () {
                          _searchController.clear();
                          controller.resetFilters();
                        }
                      : null,
                  columns: const ['Time', 'Event', 'Category', 'Status'],
                  rows: [
                    for (final row in controller.rows)
                      [
                        Text(
                          formatAdminTableDateTime(row.createdAt),
                          style: AppTypography.tableBody,
                        ),
                        AdminTableCellText(primary: row.displayEvent),
                        AdminTableCellText(
                          primary: AdminAuditCategory.labelFor(row.category),
                          primaryStyle: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        AdminStatusBadge(status: row.status),
                      ],
                  ],
                ),
                const SizedBox(height: 16),
                AdminPagination(
                  currentPage: controller.page,
                  totalItems: controller.total,
                  pageSize: controller.pageSize,
                  pageSizeOptions: const [10, 25, 50],
                  isLoading: controller.isLoading,
                  onPageChanged: controller.setPage,
                  onPageSizeChanged: controller.setPageSize,
                ),
              ],
            ),
          ),
          if (selected != null && MediaQuery.sizeOf(context).width >= 960)
            _DetailPanel(row: selected, onClose: () => controller.select(null)),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.row, required this.onClose});

  final AdminAuditLogRow row;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Event details',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(label: 'Event', value: row.displayEvent),
          _DetailLine(
            label: 'Time',
            value: DateFormat(
              'MMM d, yyyy • h:mm a',
            ).format(row.createdAt.toLocal()),
          ),
          _DetailLine(
            label: 'Category',
            value: AdminAuditCategory.labelFor(row.category),
          ),
          _DetailLine(label: 'Status', value: row.status),
          if (row.actorEmail != null)
            _DetailLine(label: 'Account', value: row.actorEmail!),
          if (row.targetType != null)
            _DetailLine(label: 'Target type', value: row.targetType!),
          if (row.targetId != null)
            _DetailLine(label: 'Target ID', value: row.targetId!),
          const SizedBox(height: 8),
          Text(row.summary, style: AppTypography.body.copyWith(height: 1.4)),
          if (row.details.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Additional details',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in row.details.entries)
              if (!_sensitiveDetailKey(entry.key))
                _DetailLine(
                  label: AdminAuditLogRow.titleCase(entry.key),
                  value: entry.value?.toString() ?? '',
                ),
          ],
        ],
      ),
    );
  }

  bool _sensitiveDetailKey(String key) {
    final k = key.toLowerCase();
    return k.contains('password') ||
        k.contains('token') ||
        k.contains('otp') ||
        k.contains('secret');
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}
