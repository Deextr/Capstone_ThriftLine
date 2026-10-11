import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_audit_logs_controller.dart';
import '../../data/admin_audit_log_models.dart';
import '../widgets/admin_audit_event_detail_dialog.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebLogsPage extends StatefulWidget {
  const AdminWebLogsPage({super.key});

  @override
  State<AdminWebLogsPage> createState() => _AdminWebLogsPageState();
}

class _AdminWebLogsPageState extends State<AdminWebLogsPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminAuditLogsController>().scheduleSearch(
      _searchController.text,
    );
  }

  void _openDetail(AdminAuditLogRow row) {
    showAdminAuditEventDetailDialog(context: context, row: row);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminAuditLogsController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () {
              _searchController.clear();
              controller.resetFilters();
            },
            children: [
              AdminSearchField(
                controller: _searchController,
                hintText: 'Search actor, action, target, or reference',
                width: 280,
                onSubmitted: controller.setSearch,
                onClear: () => controller.setSearch(''),
              ),
              AdminFilterDropdown<String>(
                value: controller.category,
                items: [
                  for (final opt in AdminAuditCategory.filterOptions)
                    DropdownMenuItem(value: opt.value, child: Text(opt.label)),
                ],
                onChanged: (v) {
                  if (v != null) controller.setCategory(v);
                },
              ),
              AdminFilterDropdown<String>(
                value: controller.actorKind,
                items: [
                  for (final opt in AdminAuditActorFilter.filterOptions)
                    DropdownMenuItem(value: opt.value, child: Text(opt.label)),
                ],
                onChanged: (v) {
                  if (v != null) controller.setActorKind(v);
                },
              ),
              AdminFilterDropdown<String>(
                value: controller.status,
                items: const [
                  DropdownMenuItem(
                    value: AdminAuditStatusFilter.all,
                    child: Text('All results'),
                  ),
                  DropdownMenuItem(
                    value: AdminAuditStatusFilter.success,
                    child: Text('Successful'),
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
          if (controller.errorMessage != null)
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
          AdminDataTable(
            isLoading: controller.isLoading,
            minWidth: 980,
            columnFlex: const [2, 3, 2, 2, 3, 1],
            onRowTap: [
              for (final row in controller.rows) () => _openDetail(row),
            ],
            emptyTitle: 'No audit logs found',
            emptyMessage: controller.hasActiveFilters
                ? 'No audit events match your filters.'
                : 'Audit logs will appear here as administrative actions occur.',
            onResetFilters: controller.hasActiveFilters
                ? () {
                    _searchController.clear();
                    controller.resetFilters();
                  }
                : null,
            columns: const [
              'Module',
              'Action',
              'Performed by',
              'Time',
              'Target',
              'Result',
            ],
            rows: [
              for (final row in controller.rows)
                [
                  Text(
                    row.moduleLabel,
                    style: AppTypography.tableBodyMedium,
                  ),
                  Text(row.displayEvent, style: AppTypography.tableBody),
                  AdminTableCellText(
                    primary: row.actorRoleDisplayLine,
                    secondary: row.actorNameDisplayLine,
                    primaryStyle: AppTypography.tableBodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatAdminTableDateTime(row.createdAt),
                    style: AppTypography.tableBody,
                  ),
                  AdminTableCellText(
                    primary: row.targetDisplayPrimary,
                    secondary: row.targetDisplaySecondary,
                    primaryStyle: AppTypography.tableBody,
                  ),
                  AdminStatusBadge(status: row.status, label: row.resultLabel),
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
    );
  }
}
