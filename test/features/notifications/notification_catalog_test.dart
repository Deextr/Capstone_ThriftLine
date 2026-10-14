import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/notifications/domain/notification_catalog.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/notification_model.dart';

NotificationModel _model({
  required NotificationType type,
  Map<String, String> data = const {},
}) {
  return NotificationModel(
    id: 'n1',
    userId: 'u1',
    type: type,
    audience: NotificationAudience.buyer,
    title: 'T',
    body: 'B',
    createdAt: DateTime.utc(2026, 10, 14, 12),
    data: data,
  );
}

void main() {
  test('orders tab includes seller system notices with order_id', () {
    final n = _model(
      type: NotificationType.system,
      data: {'order_id': 'ord-1'},
    );
    expect(notificationMatchesTab(n, 'orders'), isTrue);
    expect(notificationMatchesTab(n, 'system'), isFalse);
  });

  test('bids tab includes auction payload', () {
    final n = _model(
      type: NotificationType.system,
      data: {'auction_id': 'a1'},
    );
    expect(notificationMatchesTab(n, 'bids'), isTrue);
  });

  test('groups today and yesterday', () {
    final now = DateTime(2026, 10, 14, 18);
    final today = NotificationModel(
      id: '1',
      userId: 'u',
      type: NotificationType.system,
      audience: NotificationAudience.buyer,
      title: 'T',
      body: 'B',
      createdAt: DateTime(2026, 10, 14, 8),
    );
    final yesterday = NotificationModel(
      id: '2',
      userId: 'u',
      type: NotificationType.system,
      audience: NotificationAudience.buyer,
      title: 'T',
      body: 'B',
      createdAt: DateTime(2026, 10, 13, 8),
    );
    final groups = groupNotificationsByDay([today, yesterday], now);
    expect(groups.map((g) => g.label).toList(), ['Today', 'Yesterday']);
  });
}
