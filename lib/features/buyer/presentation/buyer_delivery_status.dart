import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/order_model.dart';

/// Shared buyer-facing delivery copy so the Track Order list and details
/// screens describe the same state with the same words.
class BuyerDeliveryStatusView {
  const BuyerDeliveryStatusView({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.channelLine,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;

  /// One-line delivery channel for list cards. Null when no rider or courier
  /// has been assigned yet.
  final String? channelLine;
}

BuyerDeliveryStatusView buyerDeliveryStatus(OrderModel order) {
  final shipment = order.shipment;
  final channel = _channelLine(order);

  if (order.isDeliveryFailed) {
    return BuyerDeliveryStatusView(
      title: 'Delivery issue',
      message: 'Delivery was not completed.',
      icon: Icons.error_outline,
      color: AppColors.warning,
      channelLine: channel,
    );
  }
  if (order.isDisputed) {
    return BuyerDeliveryStatusView(
      title: 'Under review',
      message: 'We are reviewing the reported delivery problem.',
      icon: Icons.report_problem_outlined,
      color: AppColors.warning,
      channelLine: channel,
    );
  }

  final isCourier = shipment?.isOfficialCourier == true;

  return switch (shipment?.deliveryStatus) {
    DeliveryStatus.pickedUp => BuyerDeliveryStatusView(
      title: 'Shipped',
      message: isCourier
          ? 'Your package has been shipped.'
          : 'Your parcel is with the rider.',
      icon: Icons.local_shipping_outlined,
      color: AppColors.primary,
      channelLine: channel,
    ),
    DeliveryStatus.outForDelivery ||
    DeliveryStatus.awaitingDeliveryVerification => BuyerDeliveryStatusView(
      title: 'Out for Delivery',
      message: isCourier
          ? 'Your package is on the way.'
          : 'Your rider is on the way.',
      icon: Icons.local_shipping_outlined,
      color: AppColors.primary,
      channelLine: channel,
    ),
    DeliveryStatus.deliveryVerified ||
    DeliveryStatus.inspectionPeriod => BuyerDeliveryStatusView(
      title: 'Inspect Your Order',
      message:
          'Your parcel arrived. Check it before the inspection window ends.',
      icon: Icons.fact_check_outlined,
      color: AppColors.success,
      channelLine: channel,
    ),
    DeliveryStatus.completed => const BuyerDeliveryStatusView(
      title: 'Delivered',
      message: 'Your order is complete.',
      icon: Icons.check_circle_outline,
      color: AppColors.success,
    ),
    DeliveryStatus.riderAssigned ||
    DeliveryStatus.readyForPickup => BuyerDeliveryStatusView(
      title: 'Preparing Order',
      message:
          'A rider has been assigned and the seller is preparing your item.',
      icon: Icons.inventory_2_outlined,
      color: AppColors.primary,
      channelLine: channel,
    ),
    _ => BuyerDeliveryStatusView(
      title: 'Preparing Order',
      message: 'The seller is preparing your item for delivery.',
      icon: Icons.inventory_2_outlined,
      color: AppColors.primary,
      channelLine: channel,
    ),
  };
}

String? _channelLine(OrderModel order) {
  final shipment = order.shipment;
  final courier = order.courier?.trim();
  if (shipment?.isOfficialCourier == true &&
      courier != null &&
      courier.isNotEmpty) {
    return 'Arriving via $courier';
  }
  if (shipment?.shouldShowBuyerRiderInfo == true) {
    return 'Arriving via Local Rider';
  }
  return null;
}
