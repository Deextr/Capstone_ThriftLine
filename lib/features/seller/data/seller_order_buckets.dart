import '../../../models/enums.dart';
import '../../../models/order_model.dart';
import '../../../widgets/thrift_widgets.dart';

/// Seller workspace categories. These are display/filter buckets over the
/// existing order + shipment lifecycle — not new database statuses.
enum SellerOrderBucket {
  pendingPayment,
  toShip,
  shipped,
  completed,
  cancelled;

  String get tabLabel => switch (this) {
    SellerOrderBucket.pendingPayment => 'Pending',
    SellerOrderBucket.toShip => 'To Ship',
    SellerOrderBucket.shipped => 'Shipped',
    SellerOrderBucket.completed => 'Completed',
    SellerOrderBucket.cancelled => 'Cancelled',
  };

  String get emptyTitle => switch (this) {
    SellerOrderBucket.pendingPayment => 'No pending payments',
    SellerOrderBucket.toShip => 'No orders to ship',
    SellerOrderBucket.shipped => 'No shipped orders yet',
    SellerOrderBucket.completed => 'No completed orders',
    SellerOrderBucket.cancelled => 'No cancelled orders',
  };

  String get emptyMessage => switch (this) {
    SellerOrderBucket.pendingPayment =>
      'Auction wins waiting for the buyer to pay will appear here.',
    SellerOrderBucket.toShip =>
      'Paid orders that need preparation will appear here.',
    SellerOrderBucket.shipped =>
      'Orders that are out for delivery or being inspected will appear here.',
    SellerOrderBucket.completed =>
      'Finished sales will appear here after delivery is complete.',
    SellerOrderBucket.cancelled => 'Cancelled sales will appear here.',
  };

  /// To Ship is the only bucket that needs seller action right now.
  bool get needsSellerAction => this == SellerOrderBucket.toShip;
}

/// Failed unpaid checkouts are not seller sales and must not appear in any
/// workspace tab. Every other order maps to exactly one bucket.
bool _isUnpaidFixedPriceCheckoutVoid(OrderModel order) {
  if (order.isAuctionObligation) return false;
  if (order.status != OrderStatus.cancelled) return false;
  final pay = order.paymentStatus;
  return pay != 'paid' && pay != 'refunded';
}

SellerOrderBucket? sellerOrderBucketFor(OrderModel order) {
  if (order.isFailedCheckout) return null;
  if (_isUnpaidFixedPriceCheckoutVoid(order)) return null;
  if (order.isPaymentPending) {
    // Fixed-price checkout reservations are not seller fulfillment orders.
    if (!order.isAuctionObligation) return null;
    return SellerOrderBucket.pendingPayment;
  }
  if (order.isToShip) return SellerOrderBucket.toShip;
  if (order.isShippedTab) return SellerOrderBucket.shipped;
  if (order.isCompleted) return SellerOrderBucket.completed;
  if (order.status == OrderStatus.cancelled) {
    return SellerOrderBucket.cancelled;
  }
  return null;
}

bool orderMatchesSellerBucket(OrderModel order, SellerOrderBucket bucket) {
  return sellerOrderBucketFor(order) == bucket;
}

List<OrderModel> sellerOrdersInBucket(
  Iterable<OrderModel> orders,
  SellerOrderBucket bucket,
) {
  return orders
      .where((order) => orderMatchesSellerBucket(order, bucket))
      .toList();
}

int sellerOrderCount(Iterable<OrderModel> orders, SellerOrderBucket bucket) {
  return sellerOrdersInBucket(orders, bucket).length;
}

class SellerOrderChipView {
  const SellerOrderChipView(this.label, this.variant);

  final String label;
  final BadgeVariant variant;
}

/// One seller-facing chip for list cards. Uses tab language first, then a
/// more specific delivery label inside Shipped when that helps.
SellerOrderChipView sellerOrderChip(OrderModel order) {
  final bucket = sellerOrderBucketFor(order);
  if (bucket == SellerOrderBucket.pendingPayment) {
    return const SellerOrderChipView('Pending Payment', BadgeVariant.neutral);
  }
  if (bucket == SellerOrderBucket.toShip) {
    return const SellerOrderChipView('To Ship', BadgeVariant.primary);
  }
  if (bucket == SellerOrderBucket.completed) {
    return const SellerOrderChipView('Completed', BadgeVariant.success);
  }
  if (bucket == SellerOrderBucket.cancelled) {
    return const SellerOrderChipView('Cancelled', BadgeVariant.neutral);
  }
  if (order.isDisputed) {
    return const SellerOrderChipView('Disputed', BadgeVariant.warning);
  }
  if (order.isDeliveryFailed) {
    return const SellerOrderChipView('Delivery issue', BadgeVariant.warning);
  }
  if (order.isInspecting) {
    return const SellerOrderChipView('Inspecting', BadgeVariant.success);
  }
  return const SellerOrderChipView('Shipped', BadgeVariant.primary);
}
