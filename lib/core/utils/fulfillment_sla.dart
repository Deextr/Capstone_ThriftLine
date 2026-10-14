import '../../models/community_report_model.dart';
import '../../models/enums.dart';
import '../../models/order_model.dart';

/// Seller reminder after payment if the order is still preparing.
const Duration kFulfillmentSellerNudge = Duration(hours: 24);

/// Buyer may file [seller_not_processing_order] after this wait.
const Duration kFulfillmentBuyerReportUnlock = Duration(hours: 48);

/// Admin delayed-fulfillment flag (still preparing at the 72h deadline).
const Duration kFulfillmentAdminDelayed = Duration(hours: 72);

/// Auto-cancel + escrow refund if still stuck preparing.
const Duration kFulfillmentAutoCancel = Duration(hours: 72);

enum FulfillmentReportCta { hidden, waiting, ready, underReview }

class FulfillmentSlaView {
  const FulfillmentSlaView({
    required this.cta,
    required this.stuckPreparing,
    required this.delayedForAdmin,
    this.paidAt,
    this.reportUnlocksAt,
    this.autoCancelAt,
  });

  final FulfillmentReportCta cta;
  final bool stuckPreparing;
  final bool delayedForAdmin;
  final DateTime? paidAt;
  final DateTime? reportUnlocksAt;
  final DateTime? autoCancelAt;

  bool get canSubmitFulfillmentReport => cta == FulfillmentReportCta.ready;
}

DateTime? orderPaidClock(OrderModel order) {
  if (order.paidAt != null) return order.paidAt;
  if (order.isPaidCheckout) return order.createdAt;
  return null;
}

bool isOrderStuckPreparing(OrderModel order) {
  if (!order.isPaidCheckout || order.isRefundedSale) return false;
  if (order.status == OrderStatus.cancelled ||
      order.status == OrderStatus.completed ||
      order.isCompleted ||
      order.isDisputed) {
    return false;
  }
  final shipment = order.shipment;
  if (shipment == null) return true;
  if (shipment.deliveryStatus != DeliveryStatus.sellerPreparing) return false;
  if (shipment.riderAssignedAt != null ||
      shipment.readyForPickupAt != null ||
      shipment.pickedUpAt != null) {
    return false;
  }
  return true;
}

bool isOpenOrderReport(CommunityReportModel? report) {
  if (report == null) return false;
  final status = report.status.trim().toLowerCase();
  return status == 'under_review' || status == 'needs_more_evidence';
}

FulfillmentSlaView fulfillmentSlaForOrder(
  OrderModel order, {
  CommunityReportModel? report,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final paidAt = orderPaidClock(order);
  final stuck = isOrderStuckPreparing(order);
  if (!stuck || paidAt == null) {
    return FulfillmentSlaView(
      cta: FulfillmentReportCta.hidden,
      stuckPreparing: false,
      delayedForAdmin: false,
      paidAt: paidAt,
    );
  }

  final unlocksAt = paidAt.add(kFulfillmentBuyerReportUnlock);
  final autoAt = paidAt.add(kFulfillmentAutoCancel);
  final delayed = clock.difference(paidAt) >= kFulfillmentAdminDelayed;

  if (isOpenOrderReport(report)) {
    return FulfillmentSlaView(
      cta: FulfillmentReportCta.underReview,
      stuckPreparing: true,
      delayedForAdmin: delayed,
      paidAt: paidAt,
      reportUnlocksAt: unlocksAt,
      autoCancelAt: autoAt,
    );
  }

  if (clock.isBefore(unlocksAt)) {
    return FulfillmentSlaView(
      cta: FulfillmentReportCta.waiting,
      stuckPreparing: true,
      delayedForAdmin: delayed,
      paidAt: paidAt,
      reportUnlocksAt: unlocksAt,
      autoCancelAt: autoAt,
    );
  }

  return FulfillmentSlaView(
    cta: FulfillmentReportCta.ready,
    stuckPreparing: true,
    delayedForAdmin: delayed,
    paidAt: paidAt,
    reportUnlocksAt: unlocksAt,
    autoCancelAt: autoAt,
  );
}

String formatFulfillmentRemaining(DateTime? target, {DateTime? now}) {
  if (target == null) return '';
  final remaining = target.difference(now ?? DateTime.now());
  if (remaining.isNegative || remaining.inSeconds <= 0) return 'now';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  if (hours >= 24) {
    final days = hours ~/ 24;
    final rest = hours % 24;
    if (rest == 0) return days == 1 ? '1 day' : '$days days';
    return '${days}d ${rest}h';
  }
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}
