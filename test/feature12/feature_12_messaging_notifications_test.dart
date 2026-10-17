import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/features/notifications/domain/notification_navigation.dart';
import 'package:thriftline/models/chat_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/message_model.dart';
import 'package:thriftline/models/notification_model.dart';

NotificationModel _notification({
  required NotificationType type,
  Map<String, String> data = const {},
}) {
  return NotificationModel(
    id: 'notification-1',
    userId: 'user-1',
    type: type,
    audience: NotificationAudience.system,
    title: 'Test notification',
    body: 'Test body',
    createdAt: DateTime.utc(2026, 10, 15),
    data: data,
  );
}

void _actualResult(String testId, String result) {
  debugPrint('$testId Actual Result: $result');
}

void main() {
  group('TC-MSG-UNT-001 Message Text Trimming and Empty Check', () {
    test('rejects empty and whitespace-only input, accepts visible text', () {
      final emptyResult = isValidChatMessage('');
      final whitespaceResult = isValidChatMessage('    ');
      final visibleTextResult = isValidChatMessage('Hello!');

      expect(emptyResult, isFalse);
      expect(whitespaceResult, isFalse);
      expect(visibleTextResult, isTrue);
      _actualResult(
        'TC-MSG-UNT-001',
        'empty=$emptyResult, whitespaceOnly=$whitespaceResult, '
            'visibleText=$visibleTextResult',
      );
    });
  });

  group('TC-MSG-UNT-002 Deep-Link Notification Route Resolution', () {
    test('resolves order update to the order tracking route', () {
      final notification = _notification(
        type: NotificationType.system,
        data: {'event': 'order_update', 'order_id': '123'},
      );
      final actualRoute = resolveNotificationRoute(notification);

      expect(actualRoute, '/track-order/123');
      _actualResult('TC-MSG-UNT-002/order-update', 'route=$actualRoute');
    });

    test('resolves outbid to the product route', () {
      final notification = _notification(
        type: NotificationType.outbid,
        data: {'product_id': '456'},
      );
      final actualRoute = resolveNotificationRoute(notification);

      expect(actualRoute, '/product/456');
      _actualResult('TC-MSG-UNT-002/outbid', 'route=$actualRoute');
    });

    test('resolves chat notification to the thread route', () {
      final notification = _notification(
        type: NotificationType.message,
        data: {'thread_id': '789'},
      );
      final actualRoute = resolveNotificationRoute(notification);

      expect(actualRoute, '/chat/789');
      _actualResult('TC-MSG-UNT-002/chat', 'route=$actualRoute');
    });
  });

  group('TC-MSG-UNT-003 Notification Audience Tagging Validation', () {
    test('supports buyer, seller, and admin audience tags', () {
      final buyerResult = NotificationAudience.fromString('buyer');
      final sellerResult = NotificationAudience.fromString('seller');
      final adminResult = NotificationAudience.fromString('admin');

      expect(buyerResult, NotificationAudience.buyer);
      expect(sellerResult, NotificationAudience.seller);
      expect(adminResult, NotificationAudience.system);
      _actualResult(
        'TC-MSG-UNT-003',
        'buyer=$buyerResult, seller=$sellerResult, admin=$adminResult',
      );
    });
  });

  group('TC-MSG-UNT-004 Relative Time Timestamp Formatting', () {
    final now = DateTime.utc(2026, 10, 15, 12);

    test('formats minutes, hours, and days ago', () {
      final minutesResult = formatRelativeTime(
        now.subtract(const Duration(minutes: 5)),
        now: now,
      );
      final hoursResult = formatRelativeTime(
        now.subtract(const Duration(hours: 3)),
        now: now,
      );
      final daysResult = formatRelativeTime(
        now.subtract(const Duration(days: 2)),
        now: now,
      );

      expect(minutesResult, '5m ago');
      expect(hoursResult, '3h ago');
      expect(daysResult, '2d ago');
      _actualResult(
        'TC-MSG-UNT-004',
        'fiveMinutes=$minutesResult, threeHours=$hoursResult, '
            'twoDays=$daysResult',
      );
    });
  });

  group('TC-MSG-UNT-005 Chat Unread Badge Counter Aggregation', () {
    test('sums unread counts across conversations', () {
      final actualCount = aggregateUnreadCount([2, 0, 5]);

      expect(actualCount, 7);
      _actualResult('TC-MSG-UNT-005', 'unreadCount=$actualCount');
    });
  });
}
