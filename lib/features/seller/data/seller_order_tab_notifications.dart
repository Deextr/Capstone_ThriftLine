import '../../../features/auth/domain/account_mode.dart';
import '../../../features/notifications/domain/notification_audience.dart';
import '../../../models/enums.dart';
import '../../../models/notification_model.dart';
import 'seller_order_buckets.dart';

/// Seller order tabs that surface messenger-style unread notification counts.
const sellerOrderNotificationTabs = {
  SellerOrderBucket.completed,
  SellerOrderBucket.cancelled,
};

/// Maps a seller-facing order notification to Completed or Cancelled workspace
/// tabs. Returns null for unrelated notices (paid order nudges, messages, etc.).
SellerOrderBucket? sellerOrderNotificationTerminalBucket(NotificationModel n) {
  if (!_isSellerScopedOrderNotification(n)) return null;

  final event = n.data['event']?.trim() ?? '';
  if (_cancelledEvents.contains(event)) {
    return SellerOrderBucket.cancelled;
  }

  final title = n.title.trim().toLowerCase();
  if (_isCancelledSellerOrderTitle(title)) {
    return SellerOrderBucket.cancelled;
  }

  if (n.type == NotificationType.review) {
    return SellerOrderBucket.completed;
  }

  if (_completedTitles.contains(title)) {
    return SellerOrderBucket.completed;
  }

  return null;
}

bool _isSellerScopedOrderNotification(NotificationModel n) {
  if (n.data.containsKey('payout_id')) return false;
  final orderId = n.data['order_id']?.trim() ?? '';
  if (orderId.isEmpty) return false;

  if (n.audience == NotificationAudience.seller) return true;
  if (n.audience == NotificationAudience.system &&
      n.type == NotificationType.system) {
    return true;
  }
  if (n.type == NotificationType.review) return true;
  return false;
}

const _cancelledEvents = {
  'fulfillment_auto_cancel',
  'auction_payment_expired',
  'auction_unpaid_inactive',
};

bool _isCancelledSellerOrderTitle(String titleLower) {
  if (titleLower.contains('cancel')) return true;
  if (titleLower.startsWith('payment refunded')) return true;
  if (titleLower.contains('failed to pay')) return true;
  if (titleLower.contains('without a sale')) return true;
  if (titleLower.contains('without a completed purchase')) return true;
  if (titleLower.startsWith('item return required')) return true;
  return false;
}

const _completedTitles = {
  'earnings available',
  'order completed',
  'transaction completed',
};

List<NotificationModel> sellerOrderTabUnreadNotifications({
  required Iterable<NotificationModel> items,
  required SellerOrderBucket bucket,
  required Set<String> orderIdsInBucket,
  required AccountMode accountMode,
  required bool hasSellerAccess,
  String? sellerUserId,
}) {
  if (!sellerOrderNotificationTabs.contains(bucket)) return const [];

  final visible = notificationsForAccountMode(
    items,
    accountMode,
    hasSellerAccess: hasSellerAccess,
  );

  return visible
      .where((n) {
        if (sellerUserId != null && n.userId != sellerUserId) return false;
        if (n.isRead) return false;
        if (sellerOrderNotificationTerminalBucket(n) != bucket) return false;
        final orderId = n.data['order_id']?.trim();
        return orderId != null && orderIdsInBucket.contains(orderId);
      })
      .toList(growable: false);
}

int sellerOrderTabUnreadCount({
  required Iterable<NotificationModel> items,
  required SellerOrderBucket bucket,
  required Set<String> orderIdsInBucket,
  required AccountMode accountMode,
  required bool hasSellerAccess,
  String? sellerUserId,
}) {
  return sellerOrderTabUnreadNotifications(
    items: items,
    bucket: bucket,
    orderIdsInBucket: orderIdsInBucket,
    accountMode: accountMode,
    hasSellerAccess: hasSellerAccess,
    sellerUserId: sellerUserId,
  ).length;
}

bool sellerOrderHasUnreadTabNotifications({
  required Iterable<NotificationModel> items,
  required SellerOrderBucket bucket,
  required String orderId,
  required AccountMode accountMode,
  required bool hasSellerAccess,
  String? sellerUserId,
}) {
  return sellerOrderTabUnreadNotifications(
    items: items,
    bucket: bucket,
    orderIdsInBucket: {orderId},
    accountMode: accountMode,
    hasSellerAccess: hasSellerAccess,
    sellerUserId: sellerUserId,
  ).isNotEmpty;
}

Set<String> unreadSellerOrderTabNotificationIdsForOrder({
  required Iterable<NotificationModel> items,
  required SellerOrderBucket bucket,
  required String orderId,
  required AccountMode accountMode,
  required bool hasSellerAccess,
  String? sellerUserId,
}) {
  return sellerOrderTabUnreadNotifications(
    items: items,
    bucket: bucket,
    orderIdsInBucket: {orderId},
    accountMode: accountMode,
    hasSellerAccess: hasSellerAccess,
    sellerUserId: sellerUserId,
  ).map((n) => n.id).toSet();
}
