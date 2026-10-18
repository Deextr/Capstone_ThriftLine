import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/transaction_history_format.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../../widgets/transaction_history_widgets.dart';
import '../../controllers/buyer_transaction_history_controller.dart';
import '../../data/buyer_transaction.dart';
import '../widgets/buyer_refund_status_section.dart';

class BuyerTransactionHistoryScreen extends StatefulWidget {
  const BuyerTransactionHistoryScreen({super.key});

  @override
  State<BuyerTransactionHistoryScreen> createState() =>
      _BuyerTransactionHistoryScreenState();
}

class _BuyerTransactionHistoryScreenState
    extends State<BuyerTransactionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BuyerTransactionHistoryController>();
    final initialLoad = controller.isLoading && !controller.hasAnyTransactions;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transaction History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (controller.hasAnyTransactions)
            TextButton(
              onPressed: () => _openSortSheet(context),
              child: Text(
                controller.hasDateFilter ? 'Sort · Date' : 'Sort',
                style: AppTypography.body.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: controller.load,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (initialLoad)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (controller.errorMessage != null &&
                  !controller.hasAnyTransactions)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: TransactionHistoryErrorState(
                    message: controller.errorMessage!,
                    onRetry: controller.load,
                  ),
                )
              else if (!controller.hasAnyTransactions)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: TransactionHistoryEmptyState(
                    title: 'No transactions yet',
                    message:
                        'Completed payments and refunds will appear here.',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: TransactionHistoryFilterBar(
                    selected: controller.filter,
                    onSelected: (value) => context
                        .read<BuyerTransactionHistoryController>()
                        .setFilter(value),
                    options: [
                      for (final filter in BuyerTransactionFilter.values)
                        (
                          filter,
                          filter.buyerHistoryLabel,
                          controller.countForFilter(filter),
                        ),
                    ],
                  ),
                ),
                if (controller.hasDateFilter)
                  SliverToBoxAdapter(
                    child: TransactionHistoryActiveDateChip(
                      label: controller.dateFilterSummary,
                      onClear: () {
                        context
                            .read<BuyerTransactionHistoryController>()
                            .clearDateFilter();
                        _scrollToTop();
                      },
                    ),
                  ),
                if (controller.isLoading)
                  SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      color: AppColors.primary,
                      backgroundColor: AppColors.surfaceVariant,
                      minHeight: 2,
                    ),
                  ),
                if (controller.visibleTransactions.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: TransactionHistoryEmptyFilterState(
                      message: _emptyFilterMessage(controller),
                      showClear:
                          controller.filter != BuyerTransactionFilter.all ||
                          controller.hasDateFilter,
                      onClear: () {
                        controller.resetFilters();
                        _scrollToTop();
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacingMd,
                      0,
                      AppConstants.spacingMd,
                      32,
                    ),
                    sliver: GroupedTransactionHistorySliver(
                      transactions: controller.visibleTransactions,
                      dateFor: (t) => _displayDate(t) ?? t.sortDate,
                      tileBuilder: (transaction) =>
                          _BuyerTransactionTile(transaction: transaction),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openSortSheet(BuildContext context) {
    final controller = context.read<BuyerTransactionHistoryController>();
    showBuyerTransactionHistorySortSheet(
      context: context,
      sort: controller.sort,
      hasDateFilter: controller.hasDateFilter,
      onSort: (value) {
        context.read<BuyerTransactionHistoryController>().setSort(value);
        _scrollToTop();
      },
      onPickSingleDate: (day) async {
        context
            .read<BuyerTransactionHistoryController>()
            .setDateFilterSingleDay(day);
        _scrollToTop();
      },
      onPickDateRange: (start, end) async {
        context.read<BuyerTransactionHistoryController>().setDateFilterRange(
          start,
          end,
        );
        _scrollToTop();
      },
      onClearDateFilter: () {
        context.read<BuyerTransactionHistoryController>().clearDateFilter();
        _scrollToTop();
      },
    );
  }
}

String _emptyFilterMessage(BuyerTransactionHistoryController controller) {
  if (controller.hasDateFilter) {
    return 'No transactions for ${controller.dateFilterSummary}.';
  }
  return switch (controller.filter) {
    BuyerTransactionFilter.successful =>
      'No paid orders match this filter.',
    BuyerTransactionFilter.refunded => 'No refunds yet.',
    BuyerTransactionFilter.all => 'No transactions to show.',
  };
}

DateTime? _displayDate(BuyerTransaction transaction) {
  final refunded = transaction.status != BuyerTransactionStatus.successful;
  if (refunded && transaction.refundedAt != null) {
    return transaction.refundedAt;
  }
  return transaction.paidAt;
}

class _BuyerTransactionTile extends StatelessWidget {
  const _BuyerTransactionTile({required this.transaction});

  final BuyerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final refundState = transaction.refundState;
    final refundLine =
        transaction.status == BuyerTransactionStatus.refundInProgress &&
            refundState != null
        ? buyerRefundHeadline(
            refundState,
            gcashSent: transaction.refundGcashSubmitted,
          )
        : null;
    final refundNeedsAction =
        refundState == BuyerRefundState.awaitingBuyerClaim ||
        transaction.needsGcashDetails;
    final displayDate = _displayDate(transaction);
    final isRefundFlow =
        transaction.status != BuyerTransactionStatus.successful;

    return TransactionHistoryListTile(
      productImageUrl: transaction.productImageUrl,
      title: transaction.productTitle,
      subtitle: buyerTransactionTypeSubtitle(transaction),
      amount: formatCentavos(transaction.amountCentavos),
      amountCaption: isRefundFlow ? 'Order total' : 'Paid',
      amountColor: AppColors.textPrimary,
      statusLabel: buyerTransactionStatusLabel(transaction.status),
      statusVariant: transactionHistoryStatusVariant(transaction.status),
      orderNumber: transaction.orderNumber,
      displayDate: displayDate,
      notice: refundLine,
      noticeIsAction: refundNeedsAction,
      onTap: () => _showDetails(context, transaction),
    );
  }
}

void _showDetails(BuildContext context, BuyerTransaction transaction) {
  final controller = context.read<BuyerTransactionHistoryController>();
  controller.clearGcashError();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return ChangeNotifierProvider<BuyerTransactionHistoryController>.value(
        value: controller,
        child: _TransactionDetailsSheet(paymentId: transaction.paymentId),
      );
    },
  );
}

class _TransactionDetailsSheet extends StatelessWidget {
  const _TransactionDetailsSheet({required this.paymentId});

  final String paymentId;

  @override
  Widget build(BuildContext context) {
    final transaction = context
        .watch<BuyerTransactionHistoryController>()
        .transactionById(paymentId);
    if (transaction == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text('This transaction is no longer available.'),
        ),
      );
    }
    final refunded = transaction.status != BuyerTransactionStatus.successful;
    final refundComplete =
        transaction.status == BuyerTransactionStatus.refunded;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Transaction details', style: AppTypography.subheading),
            const SizedBox(height: 4),
            Text(
              transaction.productTitle,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ThriftBadge(
                label: buyerTransactionStatusLabel(transaction.status),
                variant: transactionHistoryStatusVariant(transaction.status),
              ),
            ),
            if (transaction.hasRefund) ...[
              const SizedBox(height: 14),
              BuyerRefundStatusSection(transaction: transaction),
            ],
            const SizedBox(height: 20),
            const TransactionHistorySectionTitle(title: 'AMOUNT'),
            TransactionHistoryDetailRow(
              label: 'Amount paid',
              value: formatCentavos(transaction.amountCentavos),
              emphasis: true,
            ),
            if (refunded)
              TransactionHistoryDetailRow(
                label: refundComplete ? 'Amount refunded' : 'Refund amount',
                value: formatCentavos(
                  transaction.refundAmountCentavos ??
                      transaction.amountCentavos,
                ),
                valueColor: AppColors.warning,
              ),
            const SizedBox(height: 8),
            const TransactionHistorySectionTitle(title: 'ORDER'),
            if (transaction.orderNumber.isNotEmpty)
              TransactionHistoryDetailRow(
                label: 'Order ID',
                value: formatTransactionOrderReference(
                  transaction.orderNumber,
                ),
              ),
            if (transaction.paidAt != null)
              TransactionHistoryDetailRow(
                label: 'Paid on',
                value:
                    '${formatFullDate(transaction.paidAt!)} · ${formatTimeOfDay(transaction.paidAt!)}',
              ),
            if (refunded && transaction.refundedAt != null)
              TransactionHistoryDetailRow(
                label: 'Refund started',
                value:
                    '${formatFullDate(transaction.refundedAt!)} · ${formatTimeOfDay(transaction.refundedAt!)}',
              ),
            TransactionHistoryDetailRow(
              label: 'Payment method',
              value: transaction.methodLabel,
            ),
            if ((transaction.transactionReference ?? '').isNotEmpty)
              TransactionHistoryDetailRow(
                label: 'Reference',
                value: transaction.transactionReference!,
              ),
          ],
        ),
      ),
    );
  }
}
