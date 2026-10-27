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
import '../../../buyer/data/buyer_transaction.dart';
import '../../controllers/seller_transaction_history_controller.dart';
import '../../data/seller_transaction.dart';

class SellerTransactionHistoryScreen extends StatefulWidget {
  const SellerTransactionHistoryScreen({super.key});

  @override
  State<SellerTransactionHistoryScreen> createState() =>
      _SellerTransactionHistoryScreenState();
}

class _SellerTransactionHistoryScreenState
    extends State<SellerTransactionHistoryScreen> {
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
    final controller = context.watch<SellerTransactionHistoryController>();
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
            PopupMenuButton<BuyerTransactionSort>(
              tooltip: 'Sort',
              onSelected: (value) {
                context.read<SellerTransactionHistoryController>().setSort(
                  value,
                );
                _scrollToTop();
              },
              itemBuilder: (context) => [
                for (final option in BuyerTransactionSort.values)
                  CheckedPopupMenuItem<BuyerTransactionSort>(
                    value: option,
                    checked: controller.sort == option,
                    child: Text(option.menuLabel),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Sort',
                  style: AppTypography.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
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
                    title: 'No sales yet',
                    message:
                        'Paid orders and buyer refunds on your listings will appear here.',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: TransactionHistoryFilterBar(
                    selected: controller.filter,
                    onSelected: (value) => context
                        .read<SellerTransactionHistoryController>()
                        .setFilter(value),
                    options: [
                      for (final filter in BuyerTransactionFilter.values)
                        (
                          filter,
                          filter.sellerHistoryLabel,
                          controller.countForFilter(filter),
                        ),
                    ],
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
                      message: _emptyFilterMessage(controller.filter),
                      showClear: controller.filter != BuyerTransactionFilter.all,
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
                          _SellerTransactionTile(transaction: transaction),
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

String _emptyFilterMessage(BuyerTransactionFilter filter) =>
    switch (filter) {
      BuyerTransactionFilter.successful =>
        'No completed sales match this filter.',
      BuyerTransactionFilter.refunded => 'No buyer refunds yet.',
      BuyerTransactionFilter.all => 'No transactions to show.',
    };

DateTime? _displayDate(SellerTransaction transaction) {
  final refunded = transaction.status != BuyerTransactionStatus.successful;
  if (refunded && transaction.refundedAt != null) {
    return transaction.refundedAt;
  }
  return transaction.paidAt;
}

class _SellerTransactionTile extends StatelessWidget {
  const _SellerTransactionTile({required this.transaction});

  final SellerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final refunded = transaction.status != BuyerTransactionStatus.successful;
    final displayDate = _displayDate(transaction);
    final earningsHint = !refunded
        ? sellerTransactionEarningsLabel(transaction.escrowStatus)
        : null;
    final refundHint = sellerRefundEarningsListHint(transaction);
    final notice = refundHint ?? earningsHint;

    final amountColor = refunded
        ? AppColors.textSecondary
        : AppColors.success;

    return TransactionHistoryListTile(
      productImageUrl: transaction.productImageUrl,
      title: transaction.productTitle,
      subtitle: sellerTransactionTypeSubtitle(transaction),
      amount: formatCentavos(transaction.sellerAmountCentavos),
      amountCaption: 'Your earnings',
      amountColor: amountColor,
      statusLabel: sellerTransactionStatusLabel(transaction.status),
      statusVariant: transactionHistoryStatusVariant(transaction.status),
      orderNumber: transaction.orderNumber,
      displayDate: displayDate,
      notice: notice,
      onTap: () => _showDetails(context, transaction),
    );
  }
}

void _showDetails(BuildContext context, SellerTransaction transaction) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _TransactionDetailsSheet(transaction: transaction);
    },
  );
}

class _TransactionDetailsSheet extends StatelessWidget {
  const _TransactionDetailsSheet({required this.transaction});

  final SellerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final refunded = transaction.status != BuyerTransactionStatus.successful;
    final refundComplete =
        transaction.status == BuyerTransactionStatus.refunded;
    final earningsHint = sellerTransactionEarningsLabel(
      transaction.escrowStatus,
    );
    final refundExplanation = sellerRefundDetailExplanation(transaction);
    final commissionPercent = (transaction.commissionRate * 100).round();

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
                label: sellerTransactionStatusLabel(transaction.status),
                variant: transactionHistoryStatusVariant(transaction.status),
              ),
            ),
            if (!refunded && earningsHint.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                earningsHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (refunded && refundExplanation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                refundExplanation,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const TransactionHistorySectionTitle(title: 'EARNINGS'),
            _DetailRow(
              label: 'Buyer paid',
              value: formatCentavos(transaction.buyerPaidCentavos),
            ),
            if (transaction.subtotalCentavos > 0)
              _DetailRow(
                label: 'Product subtotal',
                value: formatCentavos(transaction.subtotalCentavos),
              ),
            if (transaction.shippingFeeCentavos > 0)
              _DetailRow(
                label: 'Shipping fee',
                value: formatCentavos(transaction.shippingFeeCentavos),
              ),
            _DetailRow(
              label: 'ThriftLine fee ($commissionPercent%)',
              value: transaction.commissionAmountCentavos > 0
                  ? '−${formatCentavos(transaction.commissionAmountCentavos)}'
                  : formatCentavos(0),
            ),
            _DetailRow(
              label: 'Fee status',
              value: sellerCommissionStatusLabel(transaction.commissionStatus),
            ),
            if (transaction.subtotalCentavos > 0)
              _DetailRow(
                label: 'Net from products',
                value: formatCentavos(transaction.netProductEarningsCentavos),
              ),
            TransactionHistoryDetailRow(
              label: 'Your earnings',
              value: formatCentavos(transaction.sellerAmountCentavos),
              emphasis: true,
              valueColor: AppColors.success,
            ),
            if (refunded) ...[
              const SizedBox(height: 8),
              const TransactionHistorySectionTitle(title: 'REFUND'),
              TransactionHistoryDetailRow(
                label: refundComplete
                    ? 'Deducted from earnings'
                    : 'Expected deduction',
                value: formatCentavos(
                  transaction.refundAmountCentavos ??
                      transaction.sellerAmountCentavos,
                ),
                valueColor: AppColors.warning,
              ),
            ],
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TransactionHistoryDetailRow(label: label, value: value);
  }
}
