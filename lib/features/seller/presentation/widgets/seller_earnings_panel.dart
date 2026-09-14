import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../data/seller_earnings.dart';

class SellerEarningsPanel extends StatelessWidget {
  const SellerEarningsPanel({
    super.key,
    required this.pendingCount,
    required this.ratingLabel,
  });

  final int pendingCount;
  final String ratingLabel;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerEarningsController>();
    final snapshot = controller.snapshot;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Earnings', style: AppTypography.subheading),
          const SizedBox(height: 4),
          Text(
            'Paid orders stay held until the sale completes or an admin decides.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          if (controller.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (controller.errorMessage != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.errorMessage!, style: AppTypography.body),
                const SizedBox(height: 12),
                ThriftButton(
                  label: 'Try again',
                  onPressed: context.read<SellerEarningsController>().load,
                ),
              ],
            )
          else if (snapshot != null)
            _LoadedPanel(
              snapshot: snapshot,
              pendingCount: pendingCount,
              ratingLabel: ratingLabel,
              isRequesting: controller.isRequesting,
              canRequest: controller.canRequestPayout,
            ),
        ],
      ),
    );
  }
}

class _LoadedPanel extends StatelessWidget {
  const _LoadedPanel({
    required this.snapshot,
    required this.pendingCount,
    required this.ratingLabel,
    required this.isRequesting,
    required this.canRequest,
  });

  final SellerEarningsSnapshot snapshot;
  final int pendingCount;
  final String ratingLabel;
  final bool isRequesting;
  final bool canRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AmountBlock(
          label: 'Available earnings',
          amountCentavos: snapshot.availableCentavos,
          hint: snapshot.availableCentavos > 0
              ? 'Ready for payout'
              : 'Released earnings appear here',
          emphasize: true,
        ),
        const SizedBox(height: 12),
        ThriftButton(
          label: snapshot.availableCentavos > 0
              ? 'Request ${formatCentavos(snapshot.availableCentavos)} payout'
              : 'No payout available',
          isLoading: isRequesting,
          onPressed: canRequest
              ? () => _confirmPayout(context, snapshot.availableCentavos)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          'This records a payout request. It does not send GCash automatically.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _AmountBlock(
                label: 'Held',
                amountCentavos: snapshot.heldCentavos,
                hint: 'Waiting for order completion',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AmountBlock(
                label: 'Refunded',
                amountCentavos: snapshot.refundedCentavos,
                hint: 'Returned to buyers',
              ),
            ),
          ],
        ),
        if (snapshot.payoutRequestedCentavos > 0) ...[
          const SizedBox(height: 12),
          _AmountBlock(
            label: 'Payout requested',
            amountCentavos: snapshot.payoutRequestedCentavos,
            hint: 'Recorded. Not sent to GCash yet.',
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            _ShopStat(label: 'To ship', value: '$pendingCount'),
            _ShopStat(label: 'Listings', value: '${snapshot.listingCount}'),
            _ShopStat(label: 'Rating', value: ratingLabel),
          ],
        ),
        if (snapshot.activity.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Recent payments', style: AppTypography.subheading),
          const SizedBox(height: 12),
          for (final item in snapshot.activity.take(8))
            _ActivityRow(item: item),
        ],
        if (snapshot.payouts.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Payout requests', style: AppTypography.subheading),
          const SizedBox(height: 12),
          for (final payout in snapshot.payouts.take(5))
            _PayoutRow(payout: payout),
        ],
      ],
    );
  }

  Future<void> _confirmPayout(BuildContext context, int amountCentavos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Request ${formatCentavos(amountCentavos)} payout?'),
        content: const Text(
          'This records a payout request for your available earnings. It does not send GCash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep earnings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Request ${formatCentavos(amountCentavos)} payout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await context
        .read<SellerEarningsController>()
        .requestPayout();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Payout request recorded.');
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({
    required this.label,
    required this.amountCentavos,
    required this.hint,
    this.emphasize = false,
  });

  final String label;
  final int amountCentavos;
  final String hint;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 4),
        Text(
          formatCentavos(amountCentavos),
          style: (emphasize ? AppTypography.heading : AppTypography.subheading)
              .copyWith(letterSpacing: -0.2),
        ),
        const SizedBox(height: 2),
        Text(hint, style: AppTypography.caption),
      ],
    );
  }
}

class _ShopStat extends StatelessWidget {
  const _ShopStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTypography.subheading),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final SellerEarningsActivity item;

  @override
  Widget build(BuildContext context) {
    final prefix = item.status == 'refunded' ? '' : '+';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.orderNumber.isNotEmpty)
                      'Order #${item.orderNumber}',
                    sellerEscrowStatusLabel(item.status),
                    if (item.sortAt != null) formatCompactDate(item.sortAt!),
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$prefix${formatCentavos(item.sellerAmountCentavos)}',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: item.status == 'refunded'
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final SellerPayoutRecord payout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              payout.requestedAt == null
                  ? 'Payout requested'
                  : 'Requested ${formatCompactDate(payout.requestedAt!)}',
              style: AppTypography.body,
            ),
          ),
          Text(
            formatCentavos(payout.amountCentavos),
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
