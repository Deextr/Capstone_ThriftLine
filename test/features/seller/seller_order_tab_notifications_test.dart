import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/features/seller/data/seller_order_buckets.dart';
import 'package:thriftline/features/seller/data/seller_order_tab_notifications.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/notification_model.dart';

NotificationModel _n({
  required String id,
  required String userId,
  NotificationType type = NotificationType.system,
  NotificationAudience audience = NotificationAudience.seller,
  String title = 'Notice',
  bool isRead = false,
  Map<String, String> data = const {},
}) {
  return NotificationModel(
    id: id,
    userId: userId,
    type: type,
    audience: audience,
    title: title,
    body: 'Body',
    createdAt: DateTime.utc(2026, 10, 18),
    isRead: isRead,
    data: data,
  );
}

void main() {
  group('seller order tab notifications', () {
    test('classifies completion and cancellation notices', () {
      expect(
        sellerOrderNotificationTerminalBucket(
          _n(
            id: '1',
            userId: 's1',
            title: 'Earnings available',
            data: {'order_id': 'o1'},
          ),
        ),
        SellerOrderBucket.completed,
      );
      expect(
        sellerOrderNotificationTerminalBucket(
          _n(
            id: '2',
            userId: 's1',
            title: 'Order auto-cancelled',
            data: {'order_id': 'o2', 'event': 'fulfillment_auto_cancel'},
          ),
        ),
        SellerOrderBucket.cancelled,
      );
      expect(
        sellerOrderNotificationTerminalBucket(
          _n(
            id: '3',
            userId: 's1',
            title: 'New paid order',
            data: {'order_id': 'o3'},
          ),
        ),
        isNull,
      );
    });

    test('counts unread notifications per tab independently', () {
      final items = [
        _n(
          id: 'c1',
          userId: 'seller-1',
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
        _n(
          id: 'c2',
          userId: 'seller-1',
          title: 'Order completed',
          data: {'order_id': 'done-2'},
        ),
        _n(
          id: 'x1',
          userId: 'seller-1',
          title: 'Order auto-cancelled',
          data: {'order_id': 'cancel-1', 'event': 'fulfillment_auto_cancel'},
        ),
        _n(
          id: 'other',
          userId: 'seller-2',
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
      ];

      expect(
        sellerOrderTabUnreadCount(
          items: items,
          bucket: SellerOrderBucket.completed,
          orderIdsInBucket: {'done-1', 'done-2'},
          accountMode: AccountMode.seller,
          hasSellerAccess: true,
          sellerUserId: 'seller-1',
        ),
        2,
      );
      expect(
        sellerOrderTabUnreadCount(
          items: items,
          bucket: SellerOrderBucket.cancelled,
          orderIdsInBucket: {'cancel-1'},
          accountMode: AccountMode.seller,
          hasSellerAccess: true,
          sellerUserId: 'seller-1',
        ),
        1,
      );
    });

    test('ignores notifications owned by another seller', () {
      final items = [
        _n(
          id: 'mine',
          userId: 'seller-1',
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
        _n(
          id: 'theirs',
          userId: 'seller-2',
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
      ];

      expect(
        sellerOrderTabUnreadCount(
          items: items,
          bucket: SellerOrderBucket.completed,
          orderIdsInBucket: {'done-1'},
          accountMode: AccountMode.seller,
          hasSellerAccess: true,
          sellerUserId: 'seller-1',
        ),
        1,
      );
    });

    test('excludes read notifications and orders outside the tab', () {
      final items = [
        _n(
          id: 'read',
          userId: 'seller-1',
          isRead: true,
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
        _n(
          id: 'orphan',
          userId: 'seller-1',
          title: 'Earnings available',
          data: {'order_id': 'missing'},
        ),
      ];

      expect(
        sellerOrderTabUnreadCount(
          items: items,
          bucket: SellerOrderBucket.completed,
          orderIdsInBucket: {'done-1'},
          accountMode: AccountMode.seller,
          hasSellerAccess: true,
        ),
        0,
      );
    });

    test('tracks multiple unread notifications on one order', () {
      final items = [
        _n(
          id: 'a',
          userId: 'seller-1',
          title: 'Earnings available',
          data: {'order_id': 'done-1'},
        ),
        _n(
          id: 'b',
          userId: 'seller-1',
          type: NotificationType.review,
          title: 'New Review',
          data: {'order_id': 'done-1', 'review_id': 'r1'},
        ),
      ];

      final ids = unreadSellerOrderTabNotificationIdsForOrder(
        items: items,
        bucket: SellerOrderBucket.completed,
        orderId: 'done-1',
        accountMode: AccountMode.seller,
        hasSellerAccess: true,
      );
      expect(ids, {'a', 'b'});
    });
  });
}
