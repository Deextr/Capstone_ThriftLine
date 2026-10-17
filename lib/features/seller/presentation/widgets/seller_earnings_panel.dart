import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_earnings_controller.dart';
import '../../data/seller_earnings.dart';
import '../../data/seller_payout_method.dart';
import 'request_payout_dialog.dart';
import 'seller_available_earnings_card.dart';
import 'seller_payout_history.dart';

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
    final open = snapshot.openPayout;
    if (open != null) {
      return 'Payout of ${formatCentavos(open.amountCentavos)} waiting for admin';
    }
    if (snapshot.availableCentavos > 0) return 'Ready for payout';
    return 'No earnings available yet';
  }

  Future<void> _confirmPayout(BuildContext context, int amountCentavos) async {
    final controller = context.read<SellerEarningsController>();
    SellerPayoutMethod? method;
    try {
      method = await controller.loadPayoutMethod();
    } catch (_) {
      if (!context.mounted) return;
      showThriftSnackBar(
        context,
        'Unable to load your GCash details.',
        isError: true,
      );
      return;
    }
    if (!context.mounted) return;

    final result = await showRequestPayoutDialog(
      context,
      availableCentavos: amountCentavos,
      method: method,
    );
    if (!context.mounted) return;
    if (result.openPaymentMethods) {
      await openPaymentMethods(context);
      return;
    }
    if (!result.confirmed) return;

    final error = await controller.requestPayout();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      'Payout request sent. An admin will transfer it to your GCash.',
    );
  }
}

class SellerEarningsFollowup extends StatelessWidget {
  const SellerEarningsFollowup({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<SellerEarningsController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();

    final hasRefunded = snapshot.refundedCentavos > 0;
    final hasWaiting = snapshot.payoutRequestedCentavos > 0;
    final hasPaid = snapshot.payoutPaidCentavos > 0;
    final hasMoneyLines =
        snapshot.heldCentavos > 0 || hasRefunded || hasWaiting || hasPaid;
    if (!hasMoneyLines && snapshot.payouts.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = <Widget>[
      if (snapshot.heldCentavos > 0)
        _MoneyLine(
          label: 'Held',
          hint: 'Waiting for delivery & completion',
          amount: formatCentavos(snapshot.heldCentavos),
        ),
      if (hasWaiting)
        _MoneyLine(
          label: 'Payout requested',
          hint: 'Waiting for an admin to send it to your GCash',
          amount: formatCentavos(snapshot.payoutRequestedCentavos),
        ),
      if (hasPaid)
        _MoneyLine(
          label: 'Paid out',
          hint: 'Sent to your GCash by an admin',
          amount: formatCentavos(snapshot.payoutPaidCentavos),
        ),
      if (hasRefunded)
        _MoneyLine(
          label: 'Refunded',
          hint: 'Returned to buyers',
          amount: formatCentavos(snapshot.refundedCentavos),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lines.isNotEmpty) ...[
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
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  lines[i],
                ],
              ],
            ),
          ),
        ],
        if (snapshot.payouts.isNotEmpty) ...[
          if (lines.isNotEmpty) const SizedBox(height: 20),
          SellerPayoutHistory(payouts: snapshot.payouts),
        ],
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
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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
