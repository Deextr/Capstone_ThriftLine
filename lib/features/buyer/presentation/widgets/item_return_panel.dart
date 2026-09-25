import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../models/enums.dart';
import '../../../../models/return_shipment.dart';
import '../../../../widgets/thrift_widgets.dart';

class ItemReturnPanel extends StatelessWidget {
  const ItemReturnPanel({
    super.key,
    required this.itemReturn,
    required this.buyerView,
    required this.isBusy,
    this.onArrange,
    this.onHandOff,
    this.onConfirmReceived,
  });

  final ReturnShipment itemReturn;
  final bool buyerView;
  final bool isBusy;
  final VoidCallback? onArrange;
  final VoidCallback? onHandOff;
  final VoidCallback? onConfirmReceived;

  @override
  Widget build(BuildContext context) {
    final steps = itemReturn.returnRequired
        ? kReturnProgressSteps
        : const <String>[];
    final active = returnProgressIndex(itemReturn.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          buyerView ? 'Item return' : 'Return to you',
          style: AppTypography.subheading,
        ),
        const SizedBox(height: 8),
        Text(
          returnStatusLabel(itemReturn.status),
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          buyerView
              ? returnStatusHint(itemReturn.status)
              : _sellerHint(itemReturn.status),
          style: AppTypography.caption,
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    i <= active ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: i <= active ? AppColors.primary : AppColors.textHint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: AppTypography.body.copyWith(
                        color: i <= active
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                        fontWeight: i == active
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (itemReturn.riderName?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(itemReturn.riderName!.trim(), style: AppTypography.body),
          if (itemReturn.riderPhone?.trim().isNotEmpty == true)
            Text(
              formatPhMobile(itemReturn.riderPhone),
              style: AppTypography.caption,
            ),
          if (itemReturn.vehicleType != null ||
              itemReturn.plateNumber?.trim().isNotEmpty == true)
            Text(
              [
                if (itemReturn.vehicleType != null)
                  DeliveryVehicleType.fromDb(itemReturn.vehicleType).label,
                if (itemReturn.plateNumber?.trim().isNotEmpty == true)
                  itemReturn.plateNumber!.trim(),
              ].join(' · '),
              style: AppTypography.caption,
            ),
          if (itemReturn.pickupScheduledAt != null)
            Text(
              'Pickup ${formatCompactDate(itemReturn.pickupScheduledAt!)}',
              style: AppTypography.caption,
            ),
          if (itemReturn.notes?.trim().isNotEmpty == true)
            Text(itemReturn.notes!.trim(), style: AppTypography.caption),
        ],
        if (!buyerView && itemReturn.needsRider && onArrange != null) ...[
          const SizedBox(height: 16),
          ThriftButton(
            label: itemReturn.status == 'rider_assigned'
                ? 'Update return rider'
                : 'Arrange return',
            isLoading: isBusy,
            onPressed: isBusy ? null : onArrange,
          ),
        ],
        if (buyerView && itemReturn.canHandOff && onHandOff != null) ...[
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Item handed to rider',
            isLoading: isBusy,
            onPressed: isBusy ? null : onHandOff,
          ),
        ],
        if (!buyerView &&
            itemReturn.canConfirmReceived &&
            onConfirmReceived != null) ...[
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Confirm item returned',
            isLoading: isBusy,
            onPressed: isBusy ? null : onConfirmReceived,
          ),
        ],
      ],
    );
  }
}

String _sellerHint(String status) => switch (status) {
  'waiting_for_rider' =>
    'Arrange a local rider. The buyer stays refunded even if you have not done this yet.',
  'rider_assigned' => 'The buyer can see the rider. Wait for the handoff.',
  'picked_up' => 'Confirm when the item is back with you.',
  'returned' => 'This return is complete. The refund is unchanged.',
  'not_required' => 'No item needs to come back. The refund is unchanged.',
  'cancelled_by_admin' =>
    'An admin stopped this return. The refund is unchanged.',
  _ => returnStatusHint(status),
};
