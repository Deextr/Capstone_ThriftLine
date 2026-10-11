import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_orders_list_controller.dart';
import '../../domain/admin_order_management.dart';
import '../widgets/admin_ui_components.dart';

class AdminWebOrdersPage extends StatelessWidget {
  const AdminWebOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminOrdersListController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          AdminPageHeader(
            title: 'Orders',
            subtitle:
                'Track customer orders, fulfillment statuses, and payment states.',
            actions: [
              OutlinedButton.icon(
                onPressed: controller.isLoading
                    ? null
                    : () => controller.load(),
                icon: Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),

          // Filters Bar
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: () => controller.resetFilters(),
            children: [
              AdminFilterDropdown<AdminUnifiedStatusFilter>(
                value: controller.unifiedStatus,
                items: [
                  for (final option in AdminUnifiedStatusFilter.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) controller.setUnifiedStatusFilter(value);
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

          // Data Table
          AdminDataTable(
            isLoading: controller.isLoading,
            emptyTitle: 'No orders found',
            emptyMessage: controller.hasActiveFilters
                ? 'No orders match this status filter. Try selecting another status.'
                : 'Orders will appear here once placed by buyers.',
            onResetFilters: controller.hasActiveFilters
                ? () => controller.resetFilters()
                : null,
            columns: const [
              'Order #',
              'Buyer',
              'Seller',
              'Amount',
              'Payment',
              'Fulfillment Status',
              'Created',
              'Actions',
            ],
            rows: [
              for (final order in controller.rows)
                [
                  Text(
                    order.orderNumber,
                    style: AppTypography.tableBodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(order.buyerName, style: AppTypography.tableBody),
                  Text(order.sellerName, style: AppTypography.tableBody),
                  Text(
                    formatCurrency(order.totalAmount),
                    style: AppTypography.tableBodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  AdminStatusBadge(
                    status: order.unifiedStatus.badgeKey,
                    label: order.unifiedStatus.label,
                  ),
                  AdminTableDateCell(dateTime: order.createdAt),
                  AdminTableLinkAction(
                    label: 'View',
                    onPressed: () => context.push(
                      RouteNames.adminOrderDetailFor(order.orderId),
                    ),
                  ),
                ],
            ],
          ),

          const SizedBox(height: 16),

          // Standardized Pagination
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
