import '../../../models/enums.dart';
import '../../../models/order_model.dart';
import '../data/delivery_payment_hold.dart';

/// How the admin orders table is sorted (server-side).
enum AdminOrdersSort { newest, oldest, amountHigh, amountLow }

extension AdminOrdersSortX on AdminOrdersSort {
  String get label => switch (this) {
    AdminOrdersSort.newest => 'Newest first',
    AdminOrdersSort.oldest => 'Oldest first',
    AdminOrdersSort.amountHigh => 'Highest amount',
    AdminOrdersSort.amountLow => 'Lowest amount',
  };
}

enum AdminOrderCategory { all, fixedPrice, auction }

extension AdminOrderCategoryX on AdminOrderCategory {
  String get label => switch (this) {
    AdminOrderCategory.all => 'All',
    AdminOrderCategory.fixedPrice => 'Fixed Price',
    AdminOrderCategory.auction => 'Auction',
  };

  String? get dbOrderType => switch (this) {
    AdminOrderCategory.all => null,
    AdminOrderCategory.fixedPrice => 'fixed_price',
    AdminOrderCategory.auction => 'auction',
  };

  static AdminOrderCategory fromQuery(String? raw) {
    final value = raw?.trim().toLowerCase();
    return switch (value) {
      'fixed_price' ||
      'fixed-price' ||
      'fixedprice' => AdminOrderCategory.fixedPrice,
      'auction' => AdminOrderCategory.auction,
      _ => AdminOrderCategory.all,
    };
  }

  String toQueryParam() => switch (this) {
    AdminOrderCategory.all => 'all',
    AdminOrderCategory.fixedPrice => 'fixed_price',
    AdminOrderCategory.auction => 'auction',
  };
}

AdminUnifiedStatusFilter adminUnifiedStatusFromQuery(String? raw) =>
    switch (raw?.trim()) {
      'cancelled_paid_review' => AdminUnifiedStatusFilter.cancelledPaidReview,
      _ => AdminUnifiedStatusFilter.any,
    };

enum AdminOrderKind { fixedPrice, auction }

String adminOrderKindLabel(AdminOrderKind kind) => switch (kind) {
  AdminOrderKind.fixedPrice => 'Fixed Price',
  AdminOrderKind.auction => 'Auction',
};

/// Authoritative order kind from persisted order row fields.
AdminOrderKind adminOrderKindFromRow({
  required String? orderType,
  required String? auctionId,
}) {
  final type = orderType?.trim().toLowerCase() ?? '';
  if (type == 'auction') return AdminOrderKind.auction;
  if (auctionId != null && auctionId.trim().isNotEmpty) {
    return AdminOrderKind.auction;
  }
  return AdminOrderKind.fixedPrice;
}

/// Filter presets for the unified status dropdown.
enum AdminUnifiedStatusFilter {
  any,
  awaitingPayment,
  preparing,
  shipped,
  completed,
  cancelled,
  cancelledPaidReview,
  refunded,
  paymentFailed,
}

extension AdminUnifiedStatusFilterX on AdminUnifiedStatusFilter {
  String get label => switch (this) {
    AdminUnifiedStatusFilter.any => 'All statuses',
    AdminUnifiedStatusFilter.awaitingPayment => 'Awaiting payment',
    AdminUnifiedStatusFilter.preparing => 'Preparing order',
    AdminUnifiedStatusFilter.shipped => 'Shipped',
    AdminUnifiedStatusFilter.completed => 'Completed',
    AdminUnifiedStatusFilter.cancelled => 'Cancelled (unpaid)',
    AdminUnifiedStatusFilter.cancelledPaidReview =>
      'Cancelled · payment review',
    AdminUnifiedStatusFilter.refunded => 'Refunded',
    AdminUnifiedStatusFilter.paymentFailed => 'Payment failed / expired',
  };
}

class AdminUnifiedOrderStatus {
  const AdminUnifiedOrderStatus({required this.label, required this.badgeKey});

  final String label;
  final String badgeKey;
}

String adminPaymentStatusLabel(String raw) {
  final s = raw.trim().toLowerCase();
  return switch (s) {
    'paid' => 'Paid',
    'pending' => 'Payment pending',
    'refunded' => 'Refunded',
    'failed' => 'Payment failed',
    'expired' => 'Checkout expired',
    _ => raw.isEmpty ? 'Unknown' : raw,
  };
}

/// Presentation-only status for the admin table and modal overview.
AdminUnifiedOrderStatus adminUnifiedOrderStatus({
  required String orderStatusDb,
  required String paymentStatus,
  String? escrowStatus,
}) {
  final os = orderStatusDb.trim().toLowerCase();
  final ps = paymentStatus.trim().toLowerCase();
  final escrow = escrowStatus?.trim().toLowerCase();

  if (ps == 'refunded' || escrow == 'refunded') {
    if (os == 'cancelled') {
      return const AdminUnifiedOrderStatus(
        label: 'Cancelled · Refunded',
        badgeKey: 'refunded',
      );
    }
    return const AdminUnifiedOrderStatus(
      label: 'Refunded',
      badgeKey: 'refunded',
    );
  }

  if (escrow == 'disputed') {
    return const AdminUnifiedOrderStatus(
      label: 'Disputed · payment on hold',
      badgeKey: 'disputed',
    );
  }

  if (os == 'cancelled') {
    if (ps == 'paid' || escrow == 'held') {
      return const AdminUnifiedOrderStatus(
        label: 'Cancelled · Payment review required',
        badgeKey: 'cancelled',
      );
    }
    if (ps == 'pending' || ps == 'failed' || ps == 'expired' || ps.isEmpty) {
      return const AdminUnifiedOrderStatus(
        label: 'Cancelled',
        badgeKey: 'cancelled',
      );
    }
    return AdminUnifiedOrderStatus(
      label: 'Cancelled · ${adminPaymentStatusLabel(ps)}',
      badgeKey: 'cancelled',
    );
  }

  if (ps == 'failed' || ps == 'expired') {
    return AdminUnifiedOrderStatus(
      label: adminPaymentStatusLabel(ps),
      badgeKey: ps,
    );
  }

  if (ps == 'pending' || os == 'pending') {
    return const AdminUnifiedOrderStatus(
      label: 'Awaiting payment',
      badgeKey: 'payment_pending',
    );
  }

  final fulfillment = orderStatusFromDb(os);
  final label = switch (fulfillment) {
    OrderStatus.paymentConfirmed => 'Payment confirmed',
    OrderStatus.preparing => 'Preparing order',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.outForDelivery => 'Out for delivery',
    OrderStatus.delivered => 'Inspecting delivery',
    OrderStatus.completed => 'Completed',
    OrderStatus.disputed => 'Disputed',
    OrderStatus.cancelled => 'Cancelled',
    OrderStatus.paymentPending || OrderStatus.placed => 'Awaiting payment',
  };

  final badgeKey = switch (fulfillment) {
    OrderStatus.completed => 'completed',
    OrderStatus.shipped || OrderStatus.outForDelivery => 'shipped',
    OrderStatus.disputed => 'disputed',
    OrderStatus.cancelled => 'cancelled',
    OrderStatus.paymentPending || OrderStatus.placed => 'payment_pending',
    _ => ps == 'paid' ? 'paid' : os,
  };

  return AdminUnifiedOrderStatus(label: label, badgeKey: badgeKey);
}

String adminOrderStatusDbFromModel(OrderModel order) {
  return switch (order.status) {
    OrderStatus.placed || OrderStatus.paymentPending => 'pending',
    OrderStatus.paymentConfirmed || OrderStatus.preparing => 'paid',
    OrderStatus.shipped => 'shipped',
    OrderStatus.outForDelivery => 'out_for_delivery',
    OrderStatus.delivered => 'delivered',
    OrderStatus.completed => 'completed',
    OrderStatus.disputed => 'disputed',
    OrderStatus.cancelled => 'cancelled',
  };
}

AdminUnifiedOrderStatus adminUnifiedOrderStatusFromOrder(
  OrderModel order, {
  DeliveryPaymentHold? escrow,
}) {
  return adminUnifiedOrderStatus(
    orderStatusDb: adminOrderStatusDbFromModel(order),
    paymentStatus: order.paymentStatus,
    escrowStatus: escrow?.status,
  );
}

class AdminOrderTimelineEvent {
  const AdminOrderTimelineEvent({
    required this.at,
    required this.title,
    this.detail,
  });

  final DateTime at;
  final String title;
  final String? detail;
}

/// Builds a chronological list from stored payment and escrow records only.
List<AdminOrderTimelineEvent> buildAdminOrderTimeline({
  required List<Map<String, dynamic>> payments,
  Map<String, dynamic>? escrow,
}) {
  final events = <AdminOrderTimelineEvent>[];

  for (final raw in payments) {
    final map = Map<String, dynamic>.from(raw);
    final created = DateTime.tryParse(map['created_at']?.toString() ?? '');
    if (created == null) continue;
    final status =
        (map['payment_status'] as String?)?.trim().toLowerCase() ?? '';
    events.add(
      AdminOrderTimelineEvent(
        at: created,
        title: 'Payment record created',
        detail: adminPaymentStatusLabel(status),
      ),
    );

    final updated = DateTime.tryParse(map['updated_at']?.toString() ?? '');
    if (updated != null &&
        updated.isAfter(created.add(const Duration(seconds: 2)))) {
      events.add(
        AdminOrderTimelineEvent(
          at: updated,
          title: 'Payment status: ${adminPaymentStatusLabel(status)}',
          detail: _paymentReferenceDetail(map),
        ),
      );
    }
  }

  if (escrow != null) {
    void addIf(String? iso, String title, {String? detail}) {
      final at = DateTime.tryParse(iso ?? '');
      if (at == null) return;
      events.add(AdminOrderTimelineEvent(at: at, title: title, detail: detail));
    }

    addIf(
      escrow['held_at']?.toString(),
      'Escrow hold started',
      detail: deliveryHoldStatusLabel('held'),
    );
    addIf(
      escrow['disputed_at']?.toString(),
      'Escrow disputed',
      detail: deliveryHoldStatusLabel('disputed'),
    );
    addIf(
      escrow['released_at']?.toString(),
      'Escrow released to seller',
      detail: escrow['release_reason']?.toString(),
    );
    addIf(
      escrow['refunded_at']?.toString(),
      'Escrow refunded to buyer',
      detail: escrow['refund_reason']?.toString(),
    );
  }

  events.sort((a, b) => b.at.compareTo(a.at));
  return events;
}

String? _paymentReferenceDetail(Map<String, dynamic> payment) {
  final parts = <String>[];
  final channel = payment['paymongo_channel']?.toString().trim();
  if (channel != null && channel.isNotEmpty) {
    parts.add(channel == 'gcash' ? 'GCash' : 'Card');
  }
  final paymongoId = payment['paymongo_payment_id']?.toString().trim();
  if (paymongoId != null && paymongoId.isNotEmpty) {
    parts.add(
      'Ref ${paymongoId.length > 12 ? '${paymongoId.substring(0, 12)}…' : paymongoId}',
    );
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

String adminOrderFulfillmentLabel(OrderModel order) {
  if (order.shipment != null) {
    return order.shipment!.deliveryStatus.label;
  }
  return orderStatusLabel(order.status);
}

String adminPaymongoChannelLabel(String? channel) {
  final c = channel?.trim().toLowerCase() ?? '';
  return switch (c) {
    'gcash' => 'GCash (PayMongo)',
    'card' => 'Card (PayMongo)',
    _ => 'PayMongo',
  };
}

bool looksLikeUuid(String value) {
  final v = value.trim();
  final pattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  return pattern.hasMatch(v);
}
