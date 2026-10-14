import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/fulfillment_sla.dart';
import '../../../../models/order_model.dart';

class FulfillmentDeadlineBanner extends StatelessWidget {
  const FulfillmentDeadlineBanner({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final sla = fulfillmentSlaForOrder(order);
    if (!sla.stuckPreparing) return const SizedBox.shrink();

    final delayed = sla.delayedForAdmin;
    final toUnlock = formatFulfillmentRemaining(sla.reportUnlocksAt);
    final toCancel = formatFulfillmentRemaining(sla.autoCancelAt);
    final title = delayed
        ? 'This order is delayed'
        : 'Ship or update this order';
    final body = delayed
        ? 'This paid order is past the 72-hour processing deadline. ThriftLine will cancel it and refund the buyer if it is still unprocessed.'
        : sla.cta == FulfillmentReportCta.ready
        ? 'Prepare this order for shipment. It will be cancelled automatically in $toCancel if it stays unprocessed.'
        : 'Prepare this order for shipment within 24 hours of payment. Automatic cancellation is in $toCancel. Buyers can report a delay in $toUnlock.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        label: '$title. $body',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: delayed
                ? AppColors.warning.withValues(alpha: 0.12)
                : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: delayed ? AppColors.warning : AppColors.primary,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: delayed ? AppColors.warning : AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(body, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
