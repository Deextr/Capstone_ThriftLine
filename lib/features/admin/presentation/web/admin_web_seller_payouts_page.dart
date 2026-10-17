import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../controllers/admin_seller_payouts_controller.dart';
import '../../domain/admin_seller_payout.dart';
import '../widgets/admin_seller_payout_detail_dialog.dart';
import '../widgets/admin_ui_components.dart';

/// Seller payout requests that an admin pays by hand through GCash.
class AdminWebSellerPayoutsPage extends StatefulWidget {
  const AdminWebSellerPayoutsPage({super.key});

  @override
  State<AdminWebSellerPayoutsPage> createState() =>
      _AdminWebSellerPayoutsPageState();
}

class _AdminWebSellerPayoutsPageState extends State<AdminWebSellerPayoutsPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminSellerPayoutsController>().scheduleSearch(
      _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _open(AdminSellerPayout payout) async {
    final controller = context.read<AdminSellerPayoutsController>();
    controller.beginAction();
    await showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: controller,
        child: AdminSellerPayoutDetailDialog(payoutId: payout.payoutId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminSellerPayoutsController>();
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
                        hintText: 'Search seller, shop, GCash, or reference',
                        width: 320,
                        onSubmitted: controller.setSearch,
                        onClear: () => controller.setSearch(''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AdminDataTable(
                    isLoading: controller.isLoading,
                    minWidth: 900,
                    columnFlex: const [3, 2, 3, 2, 2, 2],
                    emptyTitle:
                        controller.status == AdminPayoutStatusFilter.requested
                        ? 'No payouts waiting'
                        : 'No payouts found',
                    emptyMessage:
                        controller.status == AdminPayoutStatusFilter.requested
                        ? 'New seller payout requests will appear here.'
                        : 'Try another status or search.',
                    onRowTap: [
                      for (final payout in controller.rows) () => _open(payout),
                    ],
                    columns: const [
                      'Seller',
                      'Amount',
                      'Send to GCash',
                      'Requested',
                      'Status',
                      'Reference',
                    ],
                    rows: [
                      for (final payout in controller.rows)
                        [
                          AdminTableCellText(
                            primary: payout.sellerDisplayName,
                            secondary: payout.shopName != null
                                ? payout.sellerName
                                : payout.sellerEmail,
                          ),
                          Text(
                            formatCentavos(payout.amountCentavos),
                            style: AppTypography.tableBody.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AdminTableCellText(
                            primary: payout.gcashAccountName ?? 'Missing',
                            secondary: payout.gcashMobileNumber == null
                                ? null
                                : formatPhMobile(payout.gcashMobileNumber!),
                          ),
                          payout.requestedAt == null
                              ? const Text('—')
                              : AdminTablePhilippinesDateTimeCell(
                                  dateTime: payout.requestedAt!,
                                ),
                          AdminStatusBadge(
                            status: adminPayoutBadgeKey(payout.status),
                            label: adminPayoutStatusLabel(payout.status),
                          ),
                          AdminTableCellText(
                            primary: payout.gcashReference ?? '—',
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

  final AdminPayoutStatusFilter selected;
  final AdminSellerPayoutCounts counts;
  final ValueChanged<AdminPayoutStatusFilter> onSelected;

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
            for (final filter in AdminPayoutStatusFilter.values)
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
            count > 0 ? '$label ($count)' : label,
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
