import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_orders_list_controller.dart';
import '../../controllers/admin_transactions_controller.dart';
import '../widgets/admin_ui_components.dart';

/// Combined Orders & Transactions module for Admin Web.
class AdminWebOrdersTransactionsPage extends StatefulWidget {
  const AdminWebOrdersTransactionsPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminWebOrdersTransactionsPage> createState() =>
      _AdminWebOrdersTransactionsPageState();
}

class _AdminWebOrdersTransactionsPageState
    extends State<AdminWebOrdersTransactionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabController.index == 0 ? 'orders' : 'transactions';
    final uri = Uri(
      path: RouteNames.adminOrdersTransactions,
      queryParameters: {'tab': tab},
    );
    if (GoRouterState.of(context).uri.toString() != uri.toString()) {
      context.go(uri.toString());
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AdminPageHeader(
            title: 'Orders & Transactions',
            subtitle:
                'Trace orders from payment through platform fees, escrow, and settlement-related transaction records.',
          ),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'Orders'),
                    Tab(text: 'Transactions'),
                  ],
                ),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    return IndexedStack(
                      index: _tabController.index,
                      children: const [
                        _OrdersTabBody(),
                        _TransactionsTabBody(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersTabBody extends StatelessWidget {
  const _OrdersTabBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminOrdersListController>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: controller.isLoading ? null : () => controller.load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh orders'),
            ),
          ),
          const SizedBox(height: 12),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: controller.resetFilters,
            children: [
              AdminFilterDropdown<String?>(
                value: controller.statusFilter,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All order statuses'),
                  ),
                  DropdownMenuItem(
                    value: 'payment_pending',
                    child: Text('Awaiting payment'),
                  ),
                  DropdownMenuItem(
                    value: 'paid',
                    child: Text('Paid / to ship'),
                  ),
                  DropdownMenuItem(value: 'shipped', child: Text('Shipped')),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(
                    value: 'cancelled',
                    child: Text('Cancelled'),
                  ),
                ],
                onChanged: controller.setStatusFilter,
              ),
            ],
          ),
          AdminDataTable(
            isLoading: controller.isLoading,
            columnFlex: const [2, 2, 2, 2, 2, 2, 1],
            onRowTap: [
              for (final order in controller.rows)
                () =>
                    context.push(RouteNames.adminOrderDetailFor(order.orderId)),
            ],
            columns: const [
              'Order',
              'Buyer',
              'Seller',
              'Status',
              'Total',
              'Created',
              'Action',
            ],
            rows: [
              for (final order in controller.rows)
                [
                  AdminTableCellText(primary: order.orderNumber),
                  AdminTableCellText(primary: order.buyerName),
                  AdminTableCellText(primary: order.sellerName),
                  AdminStatusBadge(
                    status: order.orderStatus,
                    label: order.statusLabel,
                  ),
                  Text(
                    formatCurrency(order.totalAmount),
                    style: AppTypography.tableBody,
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
          const SizedBox(height: 12),
          AdminPagination(
            currentPage: controller.page,
            totalItems: controller.total,
            pageSize: controller.pageSize,
            isLoading: controller.isLoading,
            onPageChanged: controller.setPage,
            onPageSizeChanged: controller.setPageSize,
          ),
        ],
      ),
    );
  }
}

class _TransactionsTabBody extends StatelessWidget {
  const _TransactionsTabBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminTransactionsController>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: controller.isLoading ? null : () => controller.load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh transactions'),
            ),
          ),
          const SizedBox(height: 12),
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: controller.resetFilters,
            children: [
              AdminFilterDropdown<String?>(
                value: controller.paymentStatus,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All payment statuses'),
                  ),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'failed', child: Text('Failed')),
                  DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
                ],
                onChanged: controller.setPaymentStatus,
              ),
            ],
          ),
          AdminDataTable(
            isLoading: controller.isLoading,
            minWidth: 880,
            columnFlex: const [2, 2, 1, 2, 2, 2, 2, 1],
            columns: const [
              'Payment',
              'Order',
              'Status',
              'Gross',
              'Platform fee',
              'Seller share',
              'Paid at',
              'Action',
            ],
            rows: [
              for (final tx in controller.rows)
                [
                  AdminTableCellText(
                    primary: tx.paymentId.length > 8
                        ? tx.paymentId.substring(0, 8).toUpperCase()
                        : tx.paymentId,
                  ),
                  AdminTableCellText(
                    primary: tx.orderNumber.isNotEmpty ? tx.orderNumber : '—',
                  ),
                  AdminStatusBadge(status: tx.paymentStatus),
                  Text(
                    formatCurrency(tx.grossAmount),
                    style: AppTypography.tableBody,
                  ),
                  Text(
                    formatCurrency(tx.platformFee),
                    style: AppTypography.tableBodyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    formatCurrency(tx.sellerAmount),
                    style: AppTypography.tableBody,
                  ),
                  AdminTableDateCell(dateTime: tx.createdAt),
                  tx.orderId.isNotEmpty
                      ? AdminTableLinkAction(
                          label: 'Order',
                          onPressed: () => context.push(
                            RouteNames.adminOrderDetailFor(tx.orderId),
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
            ],
          ),
          const SizedBox(height: 12),
          AdminPagination(
            currentPage: controller.page,
            totalItems: controller.total,
            pageSize: controller.pageSize,
            isLoading: controller.isLoading,
            onPageChanged: controller.setPage,
            onPageSizeChanged: controller.setPageSize,
          ),
        ],
      ),
    );
  }
}
