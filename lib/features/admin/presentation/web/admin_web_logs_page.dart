import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/admin_audit_logs_controller.dart';
import '../../data/admin_audit_log_models.dart';
import '../../data/admin_dashboard_models.dart';
import '../widgets/admin_dashboard_widgets.dart';
import 'admin_web_table.dart';

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
          child: _DetailPanel(
            row: row,
            onClose: () => Navigator.of(ctx).pop(),
          ),
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
                Text(
                  'Logs',
                  style: AppTypography.heading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Monitor security events and administrative activity.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                _FilterBar(
                  searchController: _searchController,
                  controller: controller,
                ),
                if (controller.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.errorMessage!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AdminWebTable(
                  isLoading: controller.isLoading,
                  emptyMessage: 'No audit events match your filters.',
                  columns: const ['Time', 'Event', 'Status'],
                  rows: [
                    for (final row in controller.rows)
                      [
                        InkWell(
                          onTap: () => _openDetail(context, controller, row),
                          child: Text(
                            DateFormat('h:mm a')
                                .format(row.createdAt.toLocal()),
                            style: AppTypography.body,
                          ),
                        ),
                        InkWell(
                          onTap: () => _openDetail(context, controller, row),
                          child: Text(
                            row.displayEvent,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _openDetail(context, controller, row),
                          child: _StatusChip(status: row.status),
                        ),
                      ],
                  ],
                ),
                const SizedBox(height: 16),
                _PaginationBar(controller: controller),
              ],
            ),
          ),
          if (selected != null && MediaQuery.sizeOf(context).width >= 960)
            _DetailPanel(
              row: selected,
              onClose: () => controller.select(null),
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.controller,
  });

  final TextEditingController searchController;
  final AdminAuditLogsController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Search logs',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: controller.setSearch,
          ),
        ),
        DropdownButton<String>(
          value: controller.category,
          items: [
            for (final opt in AdminAuditCategory.filterOptions)
              DropdownMenuItem(value: opt.value, child: Text(opt.label)),
          ],
          onChanged: (v) {
            if (v != null) controller.setCategory(v);
          },
        ),
        DropdownButton<String>(
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
        PopupMenuButton<AdminDatePreset>(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(_dateLabel(controller.window)),
          ),
          onSelected: (preset) async {
            if (preset == AdminDatePreset.custom) {
              final picked = await showAdminCustomRangePicker(
                context,
                initial: controller.window,
              );
              if (picked != null) await controller.setWindow(picked);
              return;
            }
            final window = switch (preset) {
              AdminDatePreset.today => AdminDateWindow.today(),
              AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
              AdminDatePreset.last30Days => AdminDateWindow.last30Days(),
              AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
              AdminDatePreset.custom => AdminDateWindow.last7Days(),
            };
            await controller.setWindow(window);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: AdminDatePreset.today,
              child: Text('Today'),
            ),
            PopupMenuItem(
              value: AdminDatePreset.last7Days,
              child: Text('Last 7 days'),
            ),
            PopupMenuItem(
              value: AdminDatePreset.last30Days,
              child: Text('Last month'),
            ),
            PopupMenuItem(
              value: AdminDatePreset.custom,
              child: Text('Custom range'),
            ),
          ],
        ),
        TextButton(
          onPressed: () {
            searchController.clear();
            controller.resetFilters();
          },
          child: const Text('Reset filters'),
        ),
        FilledButton(
          onPressed: () => controller.setSearch(searchController.text),
          child: const Text('Search'),
        ),
      ],
    );
  }

  String _dateLabel(AdminDateWindow? window) {
    if (window == null) return 'All dates';
    return switch (window.preset) {
      AdminDatePreset.today => 'Today',
      AdminDatePreset.last7Days => 'Last 7 days',
      AdminDatePreset.last30Days => 'Last month',
      AdminDatePreset.lastYear => 'Last year',
      AdminDatePreset.custom => 'Custom range',
    };
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.controller});

  final AdminAuditLogsController controller;

  @override
  Widget build(BuildContext context) {
    final page = controller.page;
    final total = controller.pageCount;
    return Row(
      children: [
        Text(
          '${controller.total} event${controller.total == 1 ? '' : 's'}',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Previous page',
          onPressed: page > 0 && !controller.isLoading
              ? () => controller.setPage(page - 1)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          'Page ${page + 1} of $total',
          style: AppTypography.caption,
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: page + 1 < total && !controller.isLoading
              ? () => controller.setPage(page + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'success' => ('Success', AppColors.success),
      'failed' => ('Failed', AppColors.error),
      'blocked' => ('Blocked', AppColors.warning),
      _ => (AdminAuditLogRow.titleCase(status), AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
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
          _DetailLine(
            label: 'Event',
            value: row.displayEvent,
          ),
          _DetailLine(
            label: 'Time',
            value: DateFormat('MMM d, yyyy • h:mm a')
                .format(row.createdAt.toLocal()),
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
          Text(
            row.summary,
            style: AppTypography.body.copyWith(height: 1.4),
          ),
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
