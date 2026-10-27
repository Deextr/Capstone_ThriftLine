import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/admin_transactions_controller.dart';
import '../../domain/admin_order_management.dart';
import '../widgets/admin_ui_components.dart';

const kAdminPaymentsTransactionsColumnGaps = [
  16.0,
  16.0,
  16.0,
  16.0,
  16.0,
  36.0,
  16.0,
  16.0,
];

class AdminWebTransactionsPage extends StatelessWidget {
  const AdminWebTransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminTransactionsController>();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          AdminPageHeader(
            title: 'Transactions',
            subtitle:
                'Monitor escrow payment receipts, the buyer PayMongo fee, ThriftLine’s 5% seller-order commission, and seller payout amounts.',
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
              AdminFilterDropdown<String?>(
                value: controller.paymentStatus,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All Payment Statuses'),
                  ),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'failed', child: Text('Failed')),
                ],
                onChanged: controller.setPaymentStatus,
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
            minWidth: 1160,
            columnFlex: const [2, 2, 2, 2, 2, 2, 2, 2, 2],
            columnGapsAfter: kAdminPaymentsTransactionsColumnGaps,
            columnAlignments: const [
              Alignment.centerLeft,
              Alignment.centerLeft,
              Alignment.centerLeft,
              Alignment.centerRight,
              Alignment.centerRight,
              Alignment.centerRight,
              Alignment.centerRight,
              Alignment.centerLeft,
              Alignment.centerLeft,
            ],
            emptyTitle: 'No transactions found',
            emptyMessage: controller.hasActiveFilters
                ? 'No payment records match this filter. Try selecting another status.'
                : 'Payment transactions will appear here once processed.',
            onResetFilters: controller.hasActiveFilters
                ? () => controller.resetFilters()
                : null,
            columns: const [
              'Order #',
              'Buyer',
              'Seller',
              'Gross Amount',
              'PayMongo fee',
              'Commission',
              'Seller Payout',
              'Status',
              'Date',
            ],
            rows: [
              for (final row in controller.rows)
                [
                  AdminTableCellText(
                    primary: row.orderNumber.isNotEmpty ? row.orderNumber : '—',
                    primaryStyle: AppTypography.tableBodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  AdminTableCellText(primary: row.buyerName),
                  AdminTableCellText(primary: row.sellerName),
                  AdminTableMoneyCell(amount: row.grossAmount, emphasize: true),
                  AdminTableMoneyCell(amount: row.platformFee, muted: true),
                  AdminTableCommissionCell(
                    amount: row.commissionAmount,
                    statusLabel: row.commissionStatus == 'earned'
                        ? null
                        : adminOrderCommissionStatusLabel(row.commissionStatus),
                  ),
                  AdminTableMoneyCell(amount: row.sellerAmount),
                  AdminStatusBadge(status: row.paymentStatus),
                  AdminTableDateCell(dateTime: row.createdAt),
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
