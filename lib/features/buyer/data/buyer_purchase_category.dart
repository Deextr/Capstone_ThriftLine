import '../../../models/enums.dart';
import '../../../models/order_model.dart';

/// Buyer-facing tabs for [MyPurchasesScreen]. These map existing payment,
/// order, shipment, and dispute fields — not separate database statuses.
enum BuyerPurchaseCategory {
  all('all', 'All'),
  toPay('to_pay', 'To Pay'),
  paymentConfirmed('payment_confirmed', 'Payment Confirmed'),
  toReceive('to_receive', 'To Receive'),
  completed('completed', 'Completed'),
  returnRefund('return_refund', 'Return/Refund'),
  cancelled('cancelled', 'Cancelled');

  const BuyerPurchaseCategory(this.queryValue, this.label);

  final String queryValue;
  final String label;

  static BuyerPurchaseCategory? fromQuery(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    for (final cat in BuyerPurchaseCategory.values) {
      if (cat.queryValue == value.trim()) return cat;
    }
    return null;
  }
}

/// Orders that should not appear anywhere in My Purchases (e.g. abandoned
/// fixed-price checkouts restored to cart).
bool orderIncludedInMyPurchases(OrderModel order) {
  if (order.needsBuyerPayment && !order.isAuctionObligation) return false;
  if (order.isFailedCheckout && !order.isAuctionObligation) return false;
  if (order.showsAsAwaitingPayment) return true;
  if (isAuctionPaymentCancelled(order)) return true;
  return order.showsInPurchaseHistory;
}

bool isAuctionPaymentCancelled(OrderModel order) {
  if (!order.isAuctionObligation) return false;
  if (order.status == OrderStatus.cancelled) return true;
  if (order.isExpiredCheckout) return true;
  final due = order.paymentDueAt;
  if (due != null && order.needsBuyerPayment && !due.isAfter(DateTime.now())) {
    return true;
  }
  if (order.isPaymentUnsuccessful && order.isPaymentPending) return true;
  return false;
}

bool orderHasOpenReturnOrDispute(OrderModel order) =>
    order.isDisputed ||
    order.status == OrderStatus.disputed ||
    order.shipment?.deliveryStatus == DeliveryStatus.disputed ||
    order.itemReturn?.isOpen == true ||
    order.isRefundedSale;

/// Out for delivery through buyer confirmation (inspection window).
bool isOrderToReceivePhase(OrderModel order) {
  if (!order.showsInPurchaseHistory || order.isCompleted) return false;
  if (orderHasOpenReturnOrDispute(order)) return false;

  final delivery = order.shipment?.deliveryStatus;
  if (delivery == DeliveryStatus.outForDelivery ||
      delivery == DeliveryStatus.awaitingDeliveryVerification ||
      delivery == DeliveryStatus.deliveryVerified ||
      delivery == DeliveryStatus.inspectionPeriod) {
    return true;
  }
  if (order.status == OrderStatus.delivered ||
      order.status == OrderStatus.outForDelivery) {
    return true;
  }
  if (order.isDeliveryFailed) return true;
  return false;
}

/// Paid fulfillment before the parcel is out for delivery (includes picked up).
bool isOrderPaymentConfirmedPhase(OrderModel order) {
  if (!order.showsInPurchaseHistory || order.isCompleted) return false;
  if (orderHasOpenReturnOrDispute(order)) return false;
  if (isOrderToReceivePhase(order)) return false;

  final delivery = order.shipment?.deliveryStatus;
  if (delivery == null ||
      delivery == DeliveryStatus.sellerPreparing ||
      delivery == DeliveryStatus.riderAssigned ||
      delivery == DeliveryStatus.readyForPickup ||
      delivery == DeliveryStatus.pickedUp) {
    return true;
  }
  if (order.status == OrderStatus.paymentConfirmed ||
      order.status == OrderStatus.preparing ||
      order.status == OrderStatus.shipped) {
    return true;
  }
  return order.isToShip;
}

BuyerPurchaseCategory buyerPurchaseCategory(OrderModel order) {
  if (order.showsAsAwaitingPayment && order.isPaymentWindowOpen) {
    return BuyerPurchaseCategory.toPay;
  }
  if (isAuctionPaymentCancelled(order)) {
    return BuyerPurchaseCategory.cancelled;
  }
  if (orderHasOpenReturnOrDispute(order)) {
    return BuyerPurchaseCategory.returnRefund;
  }
  if (order.isCompleted) {
    return BuyerPurchaseCategory.completed;
  }
  if (isOrderToReceivePhase(order)) {
    return BuyerPurchaseCategory.toReceive;
  }
  if (isOrderPaymentConfirmedPhase(order)) {
    return BuyerPurchaseCategory.paymentConfirmed;
  }

  return BuyerPurchaseCategory.paymentConfirmed;
}

List<OrderModel> ordersForPurchaseCategory(
  Iterable<OrderModel> orders,
  BuyerPurchaseCategory category,
) {
  final included = orders.where(orderIncludedInMyPurchases);
  if (category == BuyerPurchaseCategory.all) {
    return included.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return included
      .where((order) => buyerPurchaseCategory(order) == category)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

Map<BuyerPurchaseCategory, int> purchaseCategoryCounts(
  Iterable<OrderModel> orders,
) {
  final counts = {for (final cat in BuyerPurchaseCategory.values) cat: 0};
  var allCount = 0;
  for (final order in orders) {
    if (!orderIncludedInMyPurchases(order)) continue;
    allCount++;
    final cat = buyerPurchaseCategory(order);
    counts[cat] = (counts[cat] ?? 0) + 1;
  }
  counts[BuyerPurchaseCategory.all] = allCount;
  return counts;
}

BuyerPurchaseCategory defaultPurchaseCategory() => BuyerPurchaseCategory.all;
