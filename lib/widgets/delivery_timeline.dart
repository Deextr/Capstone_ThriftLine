import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../models/enums.dart';
import '../models/order_model.dart';
import '../models/shipment_model.dart';

class DeliveryTimelineStep {
  const DeliveryTimelineStep({
    required this.title,
    required this.description,
    required this.done,
    this.current = false,
  });

  final String title;
  final String description;
  final bool done;
  final bool current;
}

List<DeliveryTimelineStep> deliveryTimelineSteps(OrderModel order) {
  final shipment = order.shipment;
  final status = shipment?.deliveryStatus;
  final failed = shipment?.isFailed == true;
  final disputed = order.isDisputed;
  final completed = order.isCompleted;

  bool reached(bool condition) => condition && !failed;

  final preparing = reached(
    shipment != null ||
        order.status == OrderStatus.preparing ||
        order.status == OrderStatus.paymentConfirmed,
  );
  final assigned = reached(
    shipment?.riderAssignedAt != null ||
        (status != null &&
            status != DeliveryStatus.sellerPreparing &&
            status != DeliveryStatus.cancelled),
  );
  final picked = reached(
    shipment?.pickedUpAt != null ||
        status == DeliveryStatus.pickedUp ||
        status == DeliveryStatus.outForDelivery ||
        status == DeliveryStatus.inspectionPeriod ||
        status == DeliveryStatus.completed ||
        status == DeliveryStatus.disputed,
  );
  final out = reached(
    shipment?.outForDeliveryAt != null ||
        status == DeliveryStatus.outForDelivery ||
        status == DeliveryStatus.inspectionPeriod ||
        status == DeliveryStatus.completed ||
        status == DeliveryStatus.disputed,
  );
  final verified = reached(shipment?.deliveryVerifiedAt != null);
  final inspecting = reached(
    shipment?.inspectionStartedAt != null ||
        status == DeliveryStatus.inspectionPeriod ||
        completed ||
        disputed,
  );

  final flags = <bool>[
    true,
    preparing,
    assigned,
    picked,
    out,
    verified,
    inspecting,
    completed,
  ];
  var current = flags.lastIndexWhere((flag) => flag);
  if (current < 0) current = 0;
  if (completed) current = 7;
  if (failed) current = picked ? 3 : current;
  if (disputed && verified) current = 6;

  const titles = [
    'Payment Confirmed',
    'Seller Preparing',
    'Rider Assigned',
    'Parcel Picked Up',
    'Out for Delivery',
    'Delivery Verification',
    'Inspection',
    'Completed',
  ];
  final descriptions = [
    'Payment confirmed through PayMongo.',
    'The seller is preparing your order.',
    'A freelance rider was assigned by the seller.',
    'The parcel has been picked up.',
    'The rider is delivering the parcel.',
    'Delivery is verified with the buyer Delivery PIN.',
    'Please inspect the item before the window ends.',
    completed
        ? 'The transaction has been completed.'
        : 'Completes after inspection if no problem is reported.',
  ];

  return List.generate(titles.length, (index) {
    return DeliveryTimelineStep(
      title: titles[index],
      description: descriptions[index],
      done: flags[index],
      current: index == current && !completed,
    );
  });
}

class DeliveryTimeline extends StatelessWidget {
  const DeliveryTimeline({
    super.key,
    required this.order,
    this.compact = false,
  });

  final OrderModel order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final steps = compact
        ? compactDeliveryTimelineSteps(order)
        : deliveryTimelineSteps(order);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

/// A buyer-friendly summary of the real delivery lifecycle. The shipment
/// statuses remain the source of truth; intermediate seller operations are
/// grouped so the buyer can scan progress without learning internal terms.
List<DeliveryTimelineStep> compactDeliveryTimelineSteps(OrderModel order) {
  final shipment = order.shipment;
  final status = shipment?.deliveryStatus;
  final isCompleted = order.isCompleted;
  final hasReachedPickup =
      status == DeliveryStatus.pickedUp ||
      status == DeliveryStatus.outForDelivery ||
      status == DeliveryStatus.awaitingDeliveryVerification ||
      status == DeliveryStatus.deliveryVerified ||
      status == DeliveryStatus.inspectionPeriod ||
      status == DeliveryStatus.disputed ||
      status == DeliveryStatus.completed;
  final hasReachedOutForDelivery =
      status == DeliveryStatus.outForDelivery ||
      status == DeliveryStatus.awaitingDeliveryVerification ||
      status == DeliveryStatus.deliveryVerified ||
      status == DeliveryStatus.inspectionPeriod ||
      status == DeliveryStatus.disputed ||
      status == DeliveryStatus.completed;
  final hasReachedDelivery =
      shipment?.deliveryVerifiedAt != null ||
      status == DeliveryStatus.deliveryVerified ||
      status == DeliveryStatus.inspectionPeriod ||
      status == DeliveryStatus.disputed ||
      status == DeliveryStatus.completed;

  final current = switch (status) {
    DeliveryStatus.pickedUp => 2,
    DeliveryStatus.outForDelivery ||
    DeliveryStatus.awaitingDeliveryVerification ||
    DeliveryStatus.deliveryFailed => 3,
    DeliveryStatus.deliveryVerified ||
    DeliveryStatus.inspectionPeriod ||
    DeliveryStatus.disputed => 4,
    DeliveryStatus.completed => 4,
    _ => 1,
  };
  final doneUntil = isCompleted ? 5 : current;
  const titles = [
    'Payment Confirmed',
    'Preparing Order',
    'Parcel Picked Up',
    'Out for Delivery',
    'Delivered',
  ];
  final descriptions = [
    'Your payment is confirmed.',
    shipment?.hasActiveRider == true
        ? 'A local rider is assigned.'
        : 'The seller is preparing your item.',
    hasReachedPickup ? 'Your parcel is with the rider.' : '',
    hasReachedOutForDelivery ? 'Your rider is on the way.' : '',
    hasReachedDelivery
        ? (isCompleted ? 'This order is complete.' : 'Delivery was verified.')
        : '',
  ];

  return List.generate(titles.length, (index) {
    return DeliveryTimelineStep(
      title: titles[index],
      description: descriptions[index],
      done: index < doneUntil,
      current: !isCompleted && index == current,
    );
  });
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast});

  final DeliveryTimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: step.current || step.done
                    ? AppColors.primary
                    : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.done
                    ? Icons.check
                    : step.current
                    ? Icons.local_shipping_outlined
                    : Icons.circle_outlined,
                color: step.done || step.current
                    ? Colors.white
                    : AppColors.textSecondary,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: step.done || step.current
                    ? AppColors.primary
                    : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: AppTypography.subheading.copyWith(
                    color: step.current ? AppColors.primary : null,
                  ),
                ),
                if (step.description.isNotEmpty)
                  Text(step.description, style: AppTypography.caption),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RiderInfoCard extends StatelessWidget {
  const RiderInfoCard({
    super.key,
    required this.shipment,
    this.buyerView = true,
  });

  final ShipmentModel shipment;
  final bool buyerView;

  @override
  Widget build(BuildContext context) {
    if (!shipment.hasRider) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery', style: AppTypography.subheading),
        const SizedBox(height: 8),
        Text('Freelance / Local Rider', style: AppTypography.body),
        Text('Seller Arranged', style: AppTypography.caption),
        const SizedBox(height: 8),
        Text(
          'Rider ${buyerView ? shipment.buyerRiderDisplayName() : (shipment.riderName ?? '—')}',
          style: AppTypography.body,
        ),
        Text(
          'Contact ${buyerView ? shipment.buyerRiderPhone() : shipment.sellerRiderPhone()}',
          style: AppTypography.body,
        ),
        Text('Vehicle ${shipment.vehicleLabel}', style: AppTypography.body),
        if (!buyerView && shipment.plateNumber != null) ...[
          Text('Plate ${shipment.plateNumber}', style: AppTypography.body),
        ],
        const SizedBox(height: 4),
        Text(shipment.deliveryStatus.label, style: AppTypography.caption),
      ],
    );
  }
}
