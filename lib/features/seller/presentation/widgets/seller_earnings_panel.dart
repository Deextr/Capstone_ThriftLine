import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../data/seller_earnings.dart';
import 'seller_available_earnings_card.dart';

class SellerEarningsPanel extends StatelessWidget {
  const SellerEarningsPanel({
    super.key,
    required this.pendingLabel,
    required this.ratingLabel,
    this.onListings,
    this.onPending,
  });

  final String pendingLabel;
  final String ratingLabel;
  final VoidCallback? onListings;
  final VoidCallback? onPending;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerEarningsController>();
    final snapshot = controller.snapshot;
    final showSkeleton = controller.isLoading && snapshot == null;

    return SellerAvailableEarningsCard(
      isLoading: showSkeleton,
      errorMessage: snapshot == null ? controller.errorMessage : null,
      amountLabel: snapshot == null
          ? null
          : formatCentavos(snapshot.availableCentavos),
      statusLine: snapshot == null ? null : _availableStatus(snapshot),
      listingsLabel: snapshot == null ? '–' : '${snapshot.listingCount}',
      pendingLabel: pendingLabel,
      ratingLabel: ratingLabel,
      showPayout: snapshot?.canRequestPayout == true,
      isRequesting: controller.isRequesting,
      onRequestPayout: snapshot == null
          ? null
          : () => _confirmPayout(context, snapshot.availableCentavos),
      onRetry: context.read<SellerEarningsController>().load,
      onListings: onListings,
      onPending: onPending,
    );
  }

  String _availableStatus(SellerEarningsSnapshot snapshot) {
    if (snapshot.availableCentavos > 0) return 'Ready for payout';
    if (snapshot.payoutRequestedCentavos > 0) return 'Payout pending';
    return 'No earnings available yet';
  }

  Future<void> _confirmPayout(BuildContext context, int amountCentavos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request payout?'),
        content: Text(
          'Record a payout of ${formatCentavos(amountCentavos)}. This does not send GCash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep earnings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request payout'),
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

class SellerEarningsFollowup extends StatelessWidget {
  const SellerEarningsFollowup({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<SellerEarningsController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();

    final hasRefunded = snapshot.refundedCentavos > 0;
    final hasPayoutPending = snapshot.payoutRequestedCentavos > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Money in progress', style: AppTypography.subheading),
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
              _MoneyLine(
                label: 'Held',
                hint: 'Waiting for delivery & completion',
                amount: formatCentavos(snapshot.heldCentavos),
              ),
              if (hasPayoutPending) ...[
                const Divider(height: 1, color: AppColors.border),
                _MoneyLine(
                  label: 'Payout pending',
                  hint: 'Awaiting GCash disbursement',
                  amount: formatCentavos(snapshot.payoutRequestedCentavos),
                ),
              ],
              if (hasRefunded) ...[
                const Divider(height: 1, color: AppColors.border),
                _MoneyLine(
                  label: 'Refunded',
                  hint: 'Returned to buyers',
                  amount: formatCentavos(snapshot.refundedCentavos),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.hint,
    required this.amount,
  });

  final String label;
  final String hint;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(hint, style: AppTypography.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
