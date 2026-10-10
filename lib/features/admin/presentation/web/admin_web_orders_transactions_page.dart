import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_orders_list_controller.dart';
import '../../data/admin_orders_service.dart';
import '../../domain/admin_order_management.dart';
import '../widgets/admin_order_detail_dialog.dart';
import '../widgets/admin_ui_components.dart';

/// Unified Orders & Transactions management for Admin Web.
class AdminWebOrdersTransactionsPage extends StatefulWidget {
  const AdminWebOrdersTransactionsPage({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  State<AdminWebOrdersTransactionsPage> createState() =>
      _AdminWebOrdersTransactionsPageState();
}

class _AdminWebOrdersTransactionsPageState
    extends State<AdminWebOrdersTransactionsPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String? _pendingDeepLinkOrderId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _pendingDeepLinkOrderId = widget.initialOrderId;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeOpenDeepLinkedOrder(),
    );
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminOrdersListController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void didUpdateWidget(covariant AdminWebOrdersTransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOrderId != oldWidget.initialOrderId &&
        widget.initialOrderId != null) {
      _pendingDeepLinkOrderId = widget.initialOrderId;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeOpenDeepLinkedOrder(),
      );
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _goCategory(AdminOrderCategory category) {
    final order = GoRouterState.of(context).uri.queryParameters['order'];
    context.read<AdminOrdersListController>().setCategory(category);
    context.go(
      RouteNames.adminOrdersTransactionsQuery(
        category: category.toQueryParam(),
        orderId: order,
      ),
    );
  }

  Future<void> _maybeOpenDeepLinkedOrder() async {
    final orderId = _pendingDeepLinkOrderId;
    if (orderId == null || orderId.isEmpty || !mounted) return;
    _pendingDeepLinkOrderId = null;

    final controller = context.read<AdminOrdersListController>();
    AdminOrderRow? row;
    for (final candidate in controller.rows) {
      if (candidate.orderId == orderId) {
        row = candidate;
        break;
      }
    }

    row ??= _placeholderRow(orderId);

    await _openOrderDetail(row);
    if (!mounted) return;
    _clearOrderQueryParam();
  }

  AdminOrderRow _placeholderRow(String orderId) {
    const unified = AdminUnifiedOrderStatus(
      label: 'Loading…',
      badgeKey: 'pending',
    );
    return AdminOrderRow(
      orderId: orderId,
      orderNumber: '',
      buyerName: '—',
      sellerName: '—',
      totalAmount: 0,
      paymentStatus: 'pending',
      orderStatus: 'pending',
      createdAt: DateTime.now(),
      orderKind: AdminOrderKind.fixedPrice,
      unifiedStatus: unified,
    );
  }

  void _clearOrderQueryParam() {
    final uri = GoRouterState.of(context).uri;
    if (!uri.queryParameters.containsKey('order')) return;
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('order');
    context.go(
      Uri(
        path: uri.path,
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
    );
  }

  Future<void> _openOrderDetail(AdminOrderRow row) async {
    final controller = context.read<AdminOrdersListController>();
    await showAdminOrderDetailDialog(
      context: context,
      summary: row,
      loadDetail: () => controller.loadOrderDetail(row.orderId),
      onOpenSiblingOrder: (siblingId) async {
        Navigator.of(context).pop();
        AdminOrderRow? sibling;
        for (final r in controller.rows) {
          if (r.orderId == siblingId) {
            sibling = r;
            break;
          }
        }
        await _openOrderDetail(sibling ?? _placeholderRow(siblingId));
      },
    );
  }

  Future<void> _pickDateRange(AdminOrdersListController controller) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: controller.dateFrom != null && controller.dateTo != null
          ? DateTimeRange(start: controller.dateFrom!, end: controller.dateTo!)
          : null,
    );
    if (range == null) return;
    await controller.setDateRange(from: range.start, to: range.end);
  }

  String _dateRangeLabel(AdminOrdersListController controller) {
    if (controller.dateFrom == null && controller.dateTo == null) {
      return 'Date range';
    }
    if (controller.dateFrom != null && controller.dateTo != null) {
      return '${formatAdminTableDate(controller.dateFrom!)} – ${formatAdminTableDate(controller.dateTo!)}';
    }
    if (controller.dateFrom != null) {
      return 'From ${formatAdminTableDate(controller.dateFrom!)}';
    }
    return 'Until ${formatAdminTableDate(controller.dateTo!)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminOrdersListController>();
    final compact = MediaQuery.sizeOf(context).width < 960;

    if (_searchController.text.isEmpty && controller.search.isNotEmpty) {
      _searchController.text = controller.search;
    }

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.all(compact ? 16 : 24),
        children: [
          OrderCategorySegmentedNav(
            selected: controller.category,
            onSelected: _goCategory,
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
                        child: Text('Retry'),
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
                        hintText: 'Search order ID, buyer, or seller',
                        width: compact ? 280 : 280,
                        onSubmitted: controller.setSearch,
                        onClear: () => controller.setSearch(''),
                      ),
                      AdminFilterDropdown<AdminUnifiedStatusFilter>(
                        value: controller.unifiedStatus,
                        items: [
                          for (final option in AdminUnifiedStatusFilter.values)
                            DropdownMenuItem(
                              value: option,
                              child: Text(option.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            controller.setUnifiedStatusFilter(value);
                          }
                        },
                      ),
                      AdminFilterDropdown<AdminOrdersSort>(
                        value: controller.sort,
                        items: [
                          for (final option in AdminOrdersSort.values)
                            DropdownMenuItem(
                              value: option,
                              child: Text(option.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) controller.setSort(value);
                        },
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isLoading
                            ? null
                            : () => _pickDateRange(controller),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(_dateRangeLabel(controller)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AdminDataTable(
                    isLoading: controller.isLoading,
                    minWidth: 920,
                    columnFlex: const [2, 2, 2, 1, 2, 2, 2],
                    onRowTap: [
                      for (final order in controller.rows)
                        () => _openOrderDetail(order),
                    ],
                    columns: const [
                      'Order ID',
                      'Buyer',
                      'Seller',
                      'Order type',
                      'Total',
                      'Status',
                      'Date & time',
                    ],
                    rows: [
                      for (final order in controller.rows)
                        [
                          AdminTableCellText(primary: order.orderNumber),
                          AdminTableCellText(primary: order.buyerName),
                          AdminTableCellText(primary: order.sellerName),
                          AdminOrderTypeBadge(
                            label: adminOrderKindLabel(order.orderKind),
                          ),
                          Text(
                            formatCurrency(order.totalAmount),
                            style: AppTypography.tableBody,
                          ),
                          AdminStatusBadge(
                            status: order.unifiedStatus.badgeKey,
                            label: order.unifiedStatus.label,
                          ),
                          AdminTablePhilippinesDateTimeCell(
                            dateTime: order.createdAt,
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

class OrderCategorySegmentedNav extends StatelessWidget {
  const OrderCategorySegmentedNav({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AdminOrderCategory selected;
  final ValueChanged<AdminOrderCategory> onSelected;

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
            for (final cat in AdminOrderCategory.values)
              _OrderCategoryTab(
                label: cat.label,
                isSelected: selected == cat,
                onTap: () => onSelected(cat),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderCategoryTab extends StatelessWidget {
  const _OrderCategoryTab({
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
            gradient: isSelected ? AppGradients.primaryGradientLight : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: isSelected
                  ? AppColors.primaryDark
                  : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
