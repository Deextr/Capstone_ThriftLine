import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../data/seller_earnings.dart';

/// Recent payout requests and what an admin did with each one.
class SellerPayoutHistory extends StatelessWidget {
  const SellerPayoutHistory({super.key, required this.payouts});

  final List<SellerPayoutRecord> payouts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payouts', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text(
          'An admin sends each payout to your GCash by hand and adds the '
          'reference here.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < payouts.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                _PayoutRow(payout: payouts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final SellerPayoutRecord payout;

  BadgeVariant get _variant => switch (payout.status) {
    SellerPayoutStatus.requested => BadgeVariant.primary,
    SellerPayoutStatus.paid => BadgeVariant.success,
    SellerPayoutStatus.rejected => BadgeVariant.error,
    SellerPayoutStatus.cancelled => BadgeVariant.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerEarningsController>();
    final cancelling = controller.cancellingPayoutId == payout.payoutId;
    final details = <String>[
      if (payout.requestedAt != null)
        'Requested ${formatFullDate(payout.requestedAt!)}',
      if (payout.status == SellerPayoutStatus.paid &&
          payout.transferredAt != null)
        'Sent ${formatFullDate(payout.transferredAt!)}',
      if (payout.status == SellerPayoutStatus.cancelled &&
          payout.cancelledAt != null)
        'Cancelled ${formatFullDate(payout.cancelledAt!)}',
    ];
    final mobile = maskMobileNumber(payout.gcashMobileNumber);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatCentavos(payout.amountCentavos),
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ThriftBadge(
                label: sellerPayoutStatusLabel(payout.status),
                variant: _variant,
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(details.join(' · '), style: AppTypography.caption),
          ],
          if (mobile.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('GCash $mobile', style: AppTypography.caption),
          ],
          if (payout.status == SellerPayoutStatus.paid &&
              payout.gcashReference != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              'GCash reference ${payout.gcashReference}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (payout.status == SellerPayoutStatus.rejected &&
              payout.rejectionReason != null) ...[
            const SizedBox(height: 4),
            Text(
              payout.rejectionReason!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 2),
            Text(
              'The amount is back in your available earnings.',
              style: AppTypography.caption,
            ),
          ],
          if (payout.canCancel) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                  foregroundColor: AppColors.error,
                ),
                onPressed: cancelling ? null : () => _confirmCancel(context),
                child: Text(cancelling ? 'Cancelling…' : 'Cancel request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel payout request?'),
        content: Text(
          '${formatCentavos(payout.amountCentavos)} goes back to your '
          'available earnings. You can request it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await context.read<SellerEarningsController>().cancelPayout(
      payout.payoutId,
    );
    if (!context.mounted) return;
    showThriftSnackBar(
      context,
      error ?? 'Payout request cancelled.',
      isError: error != null,
    );
  }
}
