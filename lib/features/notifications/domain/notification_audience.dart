import '../../../features/auth/domain/account_mode.dart';
import '../../../models/enums.dart';
import '../../../models/notification_model.dart';

/// Whether a notification belongs in the active Buyer/Seller workspace.
bool notificationVisibleInAccountMode(
  NotificationModel notification,
  AccountMode mode, {
  required bool hasSellerAccess,
}) {
  if (!hasSellerAccess) {
    return notification.audience != NotificationAudience.seller;
  }
  return switch (notification.audience) {
    NotificationAudience.system => true,
    NotificationAudience.buyer => mode == AccountMode.buyer,
    NotificationAudience.seller => mode == AccountMode.seller,
  };
}

List<NotificationModel> notificationsForAccountMode(
  Iterable<NotificationModel> items,
  AccountMode mode, {
  required bool hasSellerAccess,
}) {
  return items
      .where(
        (n) => notificationVisibleInAccountMode(
          n,
          mode,
          hasSellerAccess: hasSellerAccess,
        ),
      )
      .toList();
}

int unreadNotificationsForAccountMode(
  Iterable<NotificationModel> items,
  AccountMode mode, {
  required bool hasSellerAccess,
}) {
  return notificationsForAccountMode(
    items,
    mode,
    hasSellerAccess: hasSellerAccess,
  ).where((n) => !n.isRead).length;
}

List<String> notificationAudienceDbValuesForMode(
  AccountMode mode, {
  required bool hasSellerAccess,
}) {
  if (!hasSellerAccess) {
    return ['buyer', 'system'];
  }
  return switch (mode) {
    AccountMode.buyer => ['buyer', 'system'],
    AccountMode.seller => ['seller', 'system'],
  };
}
