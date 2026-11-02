import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/buyer_order_refund.dart';
import '../../data/buyer_transaction.dart';
import '../../../../models/return_shipment.dart';

class BuyerRefundReturnProgress extends StatelessWidget {
  const BuyerRefundReturnProgress({
    super.key,
    required this.refundState,
    required this.gcashSubmitted,
    this.itemReturn,
  });

  final BuyerRefundState? refundState;
  final bool gcashSubmitted;
  final ReturnShipment? itemReturn;

  @override
  Widget build(BuildContext context) {
    final steps = buildRefundReturnProgressSteps(
      refundState: refundState,
      gcashSubmitted: gcashSubmitted,
      itemReturn: itemReturn,
    );
    if (steps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Refund & return progress', style: AppTypography.subheading),
        const SizedBox(height: 12),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconFor(step.state),
                  size: 18,
                  color: _colorFor(step.state),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.label,
                    style: AppTypography.body.copyWith(
                      color: step.state == RefundReturnStepState.upcoming
                          ? AppColors.textHint
                          : AppColors.textPrimary,
                      fontWeight: step.state == RefundReturnStepState.current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _iconFor(RefundReturnStepState state) => switch (state) {
    RefundReturnStepState.done => Icons.check_circle,
    RefundReturnStepState.current => Icons.radio_button_checked,
    RefundReturnStepState.upcoming => Icons.circle_outlined,
  };

  Color _colorFor(RefundReturnStepState state) => switch (state) {
    RefundReturnStepState.done => AppColors.primary,
    RefundReturnStepState.current => AppColors.warning,
    RefundReturnStepState.upcoming => AppColors.textHint,
  };
}
