import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_buyer_refunds_controller.dart';
import '../../data/admin_refunds_service.dart';
import '../../data/delivery_payment_hold.dart';
import '../../domain/admin_buyer_refund.dart';
import '../widgets/admin_buyer_refund_detail_dialog.dart';
import '../widgets/admin_ui_components.dart';

/// Buyer refunds after an order is refunded: manual GCash recording and legacy PayMongo status.
class AdminWebBuyerRefundsPage extends StatefulWidget {
  const AdminWebBuyerRefundsPage({super.key});

  @override
  State<AdminWebBuyerRefundsPage> createState() =>
      _AdminWebBuyerRefundsPageState();
}

class _AdminWebBuyerRefundsPageState extends State<AdminWebBuyerRefundsPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminBuyerRefundsController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _open(AdminBuyerRefundRow row) async {
    final refundsController = context.read<AdminBuyerRefundsController>();
    final service = AdminRefundsService(context.read<SupabaseService>());
    await showDialog<void>(
      context: context,
      builder: (_) => MultiProvider(
        providers: [ChangeNotifierProvider.value(value: refundsController)],
        child: AdminBuyerRefundDetailDialog(summary: row, service: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminBuyerRefundsController>();
    final compact = MediaQuery.sizeOf(context).width < 960;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        children: [
          _StatusTabs(
            selected: controller.status,
            counts: controller.counts,
            onSelected: controller.setStatus,
          ),
          const SizedBox(height: 16),
          if (controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.errorMessage!,
                          style: AppTypography.body,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        hintText: 'Search order, buyer, PayMongo refund, GCash',
                        width: 340,
                        onSubmitted: controller.setSearch,
                        onClear: () => controller.setSearch(''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AdminDataTable(
                    isLoading: controller.isLoading,
                    minWidth: 760,
                    columnFlex: const [3, 3, 2, 3, 2, 1],
                    columnAlignments: const [
                      Alignment.centerLeft,
                      Alignment.centerLeft,
                      Alignment.centerLeft,
                      Alignment.centerLeft,
                      Alignment.centerLeft,
                      Alignment.center,
                    ],
                    emptyTitle:
                        controller.status ==
                            AdminBuyerRefundStatusFilter.needsAction
                        ? 'Nothing needs action'
                        : 'No refunds found',
                    emptyMessage:
                        controller.status ==
                            AdminBuyerRefundStatusFilter.needsAction
                        ? 'Manual GCash refunds waiting for proof or details show up here.'
                        : 'Try another tab or adjust your search.',
                    onRowTap: [
                      for (final row in controller.rows) () => _open(row),
                    ],
                    columns: const [
                      'Order',
                      'Buyer',
                      'Amount',
                      'Status',
                      'Date and time',
                      '',
                    ],
                    rows: [
                      for (final row in controller.rows)
                        [
                          Text(
                            row.orderNumber,
                            style: AppTypography.tableBody.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AdminTableCellText(
                            primary: row.buyerName,
                            secondary: row.buyerEmail,
                          ),
                          Text(
                            formatCentavos(row.amountCentavos),
                            style: AppTypography.tableBody.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AdminStatusBadge(
                            status: adminBuyerRefundBadgeKey(row.refundState),
                            label: adminRefundStateLabel(row.refundState),
                          ),
                          row.refundedAt == null
                              ? Text(
                                  '—',
                                  style: AppTypography.tableBody.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : AdminTablePhilippinesDateTimeCell(
                                  dateTime: row.refundedAt!,
                                ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ],
                    ],
                  ),
                  const SizedBox(height: 12),
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
          ),
        ],
      ),
    );
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final AdminBuyerRefundStatusFilter selected;
  final AdminBuyerRefundCounts counts;
  final ValueChanged<AdminBuyerRefundStatusFilter> onSelected;

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
            for (final filter in AdminBuyerRefundStatusFilter.values)
              _StatusTab(
                label: filter.label,
                count: counts.forFilter(filter),
                isSelected: selected == filter,
                onTap: () => onSelected(filter),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.body.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
