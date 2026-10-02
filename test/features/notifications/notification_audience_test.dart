import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/features/notifications/domain/notification_audience.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/notification_model.dart';

NotificationModel _n({
  required NotificationAudience audience,
  bool isRead = false,
}) {
  return NotificationModel(
    id: 'id-${audience.name}',
    userId: 'user-1',
    type: NotificationType.system,
    audience: audience,
    title: 'Title',
    body: 'Body',
    createdAt: DateTime.utc(2026, 1, 1),
    isRead: isRead,
  );
}

void main() {
  group('notification audience by account mode', () {
    test('buyer mode shows buyer and system only', () {
      final items = [
        _n(audience: NotificationAudience.buyer),
        _n(audience: NotificationAudience.seller),
        _n(audience: NotificationAudience.system),
      ];
      final visible = notificationsForAccountMode(
        items,
        AccountMode.buyer,
        hasSellerAccess: true,
      );
      expect(visible.map((n) => n.audience).toList(), [
        NotificationAudience.buyer,
        NotificationAudience.system,
      ]);
    });

    test('seller mode shows seller and system only', () {
      final items = [
        _n(audience: NotificationAudience.buyer, isRead: true),
        _n(audience: NotificationAudience.seller),
        _n(audience: NotificationAudience.system, isRead: true),
      ];
      final visible = notificationsForAccountMode(
        items,
        AccountMode.seller,
        hasSellerAccess: true,
      );
      expect(visible.map((n) => n.audience).toList(), [
        NotificationAudience.seller,
        NotificationAudience.system,
      ]);
      expect(
        unreadNotificationsForAccountMode(
          items,
          AccountMode.seller,
          hasSellerAccess: true,
        ),
        1,
      );
    });

    test('buyer-only accounts hide seller audience', () {
      final items = [
        _n(audience: NotificationAudience.buyer),
        _n(audience: NotificationAudience.seller),
      ];
      final visible = notificationsForAccountMode(
        items,
        AccountMode.buyer,
        hasSellerAccess: false,
      );
      expect(visible.length, 1);
      expect(visible.first.audience, NotificationAudience.buyer);
    });

    test('mark-all-read audiences per mode', () {
      expect(
        notificationAudienceDbValuesForMode(
          AccountMode.buyer,
          hasSellerAccess: true,
        ),
        ['buyer', 'system'],
      );
      expect(
        notificationAudienceDbValuesForMode(
          AccountMode.seller,
          hasSellerAccess: true,
        ),
        ['seller', 'system'],
      );
    });
  });
}
