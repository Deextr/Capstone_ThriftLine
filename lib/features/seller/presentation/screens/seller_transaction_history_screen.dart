import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
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
        title: const Text('Seller transaction history'),
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
                  child: _ErrorState(
                    message: controller.errorMessage!,
                    onRetry: controller.load,
                  ),
                )
              else if (!controller.hasAnyTransactions)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyHistoryState(),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _HistoryHeader(controller: controller),
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
                    child: _EmptyFilterState(
                      filter: controller.filter,
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
                    sliver: SliverList.separated(
                      itemCount: controller.visibleTransactions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _TransactionCard(
                          transaction: controller.visibleTransactions[index],
                        );
                      },
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

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.controller});

  final SellerTransactionHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        12,
        AppConstants.spacingMd,
        16,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < BuyerTransactionFilter.values.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _FilterChip(
                label: BuyerTransactionFilter.values[i].label,
                count: controller.countForFilter(
                  BuyerTransactionFilter.values[i],
                ),
                selected: controller.filter == BuyerTransactionFilter.values[i],
                onTap: () => context
                    .read<SellerTransactionHistoryController>()
                    .setFilter(BuyerTransactionFilter.values[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: AppTypography.caption.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction});

  final SellerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final refunded = transaction.status != BuyerTransactionStatus.successful;
    final statusVariant = _statusVariant(transaction.status);
    final displayDate = refunded && transaction.refundedAt != null
        ? transaction.refundedAt!
        : transaction.paidAt;
    final refundState = transaction.refundState;
    final refundLine =
        transaction.status == BuyerTransactionStatus.refundInProgress &&
            refundState != null
        ? buyerRefundHeadline(refundState)
        : null;
    final earningsHint = !refunded
        ? sellerTransactionEarningsLabel(transaction.escrowStatus)
        : null;

    return Semantics(
      button: true,
      label:
          '${transaction.productTitle}, ${buyerTransactionStatusLabel(transaction.status)}, ${formatCentavos(transaction.sellerAmountCentavos)}',
      child: ThriftCard(
        onTap: () => _showDetails(context, transaction),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    transaction.productTitle,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatCentavos(transaction.sellerAmountCentavos),
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Your earnings',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (refunded &&
                transaction.refundAmountCentavos != null &&
                transaction.refundAmountCentavos! > 0) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  transaction.status == BuyerTransactionStatus.refunded
                      ? 'Reversed ${formatCentavos(transaction.refundAmountCentavos!)}'
                      : 'Reversal ${formatCentavos(transaction.refundAmountCentavos!)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (refundLine != null) ...[
              const SizedBox(height: 6),
              Text(
                refundLine,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (earningsHint != null && earningsHint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                earningsHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ThriftBadge(
                  label: buyerTransactionStatusLabel(transaction.status),
                  variant: statusVariant,
                ),
                if (transaction.orderNumber.isNotEmpty)
                  Text(
                    transaction.orderNumber,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (displayDate != null)
                  Text(
                    formatFullDate(displayDate),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                Text(
                  transaction.methodLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No sales yet',
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Paid orders and buyer refunds on your listings will appear here.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.filter, required this.onClear});

  final BuyerTransactionFilter filter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      BuyerTransactionFilter.successful =>
        'No successful sales match this filter.',
      BuyerTransactionFilter.refunded => 'No buyer refunds yet.',
      BuyerTransactionFilter.all => 'No transactions to show.',
    };
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (filter != BuyerTransactionFilter.all) ...[
            const SizedBox(height: 16),
            ThriftButton(
              label: 'Show all transactions',
              variant: ThriftButtonVariant.outline,
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Couldn\'t load transactions',
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ThriftButton(
            label: 'Try again',
            variant: ThriftButtonVariant.outline,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

BadgeVariant _statusVariant(BuyerTransactionStatus status) => switch (status) {
  BuyerTransactionStatus.successful => BadgeVariant.success,
  BuyerTransactionStatus.refundInProgress => BadgeVariant.primary,
  BuyerTransactionStatus.refunded => BadgeVariant.warning,
};

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
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ThriftBadge(
                label: buyerTransactionStatusLabel(transaction.status),
                variant: _statusVariant(transaction.status),
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
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Your earnings',
              value: formatCentavos(transaction.sellerAmountCentavos),
            ),
            _DetailRow(
              label: 'Buyer paid',
              value: formatCentavos(transaction.buyerPaidCentavos),
            ),
            if (refunded)
              _DetailRow(
                label: refundComplete ? 'Earnings reversed' : 'Reversal amount',
                value: formatCentavos(
                  transaction.refundAmountCentavos ??
                      transaction.sellerAmountCentavos,
                ),
              ),
            if (transaction.paidAt != null)
              _DetailRow(
                label: 'Paid on',
                value: formatFullDate(transaction.paidAt!),
              ),
            if (refunded && transaction.refundedAt != null)
              _DetailRow(
                label: 'Refund started',
                value: formatFullDate(transaction.refundedAt!),
              ),
            if (transaction.orderNumber.isNotEmpty)
              _DetailRow(label: 'Order', value: transaction.orderNumber),
            _DetailRow(label: 'Method', value: transaction.methodLabel),
            if ((transaction.transactionReference ?? '').isNotEmpty)
              _DetailRow(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.body,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
