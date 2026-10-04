import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/features/notifications/domain/notification_audience.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/notification_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Interactive notification inbox harness with filtering and read/unread state.
class _NotificationInboxHarness extends StatefulWidget {
  const _NotificationInboxHarness({
    required this.notifications,
    required this.accountMode,
    required this.hasSellerAccess,
    required this.onNotificationTapped,
  });

  final List<NotificationModel> notifications;
  final AccountMode accountMode;
  final bool hasSellerAccess;
  final void Function(NotificationModel notification) onNotificationTapped;

  @override
  State<_NotificationInboxHarness> createState() =>
      _NotificationInboxHarnessState();
}

class _NotificationInboxHarnessState extends State<_NotificationInboxHarness> {
  late List<NotificationModel> _items;

  @override
  void initState() {
    super.initState();
    _items = notificationsForAccountMode(
      widget.notifications,
      widget.accountMode,
      hasSellerAccess: widget.hasSellerAccess,
    );
  }

  void _markAsRead(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(isRead: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$unreadCount unread',
                key: const Key('notif-unread-count'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              key: Key('notif-empty-state'),
              child: Text('No notifications'),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, index) {
                final n = _items[index];
                return ListTile(
                  key: Key('notif-item-$index'),
                  leading: Icon(
                    n.isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                    color: n.isRead ? Colors.grey : const Color(0xFF6C5CE7),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(n.body),
                  trailing: n.isRead
                      ? null
                      : ThriftBadge(
                          label: 'New',
                          variant: BadgeVariant.primary,
                        ),
                  onTap: () {
                    _markAsRead(index);
                    widget.onNotificationTapped(n);
                  },
                );
              },
            ),
    );
  }
}

NotificationModel _notif({
  required String id,
  required NotificationType type,
  required NotificationAudience audience,
  required String title,
  required String body,
  bool isRead = false,
  Map<String, String> data = const {},
}) =>
    NotificationModel(
      id: id,
      userId: 'buyer-qa-1',
      type: type,
      audience: audience,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      isRead: isRead,
      data: data,
    );

void notificationIntegrationTests() {
  qaGroup('Notification Inbox Integration Flow', () {
    qaIntegrationTest(
        'buyer workspace filters seller notifications and manages read state', (
      tester,
    ) async {
      final notifications = [
        _notif(
          id: 'n-1',
          type: NotificationType.outbid,
          audience: NotificationAudience.buyer,
          title: 'You were outbid!',
          body: 'Someone placed a higher bid on Vintage Denim Jacket.',
        ),
        _notif(
          id: 'n-2',
          type: NotificationType.shipped,
          audience: NotificationAudience.buyer,
          title: 'Order Shipped',
          body: 'Your order TL-8821 has been shipped.',
        ),
        _notif(
          id: 'n-3',
          type: NotificationType.orderConfirmed,
          audience: NotificationAudience.seller,
          title: 'New Order Received',
          body: 'A buyer placed an order for Vintage Leather Jacket.',
        ),
        _notif(
          id: 'n-4',
          type: NotificationType.system,
          audience: NotificationAudience.system,
          title: 'System Maintenance',
          body: 'ThriftLine will be under maintenance tonight at 2:00 AM.',
          isRead: true,
        ),
      ];

      NotificationModel? tappedNotification;

      await tester.pumpWidget(
        MaterialApp(
          home: _NotificationInboxHarness(
            notifications: notifications,
            accountMode: AccountMode.buyer,
            hasSellerAccess: true,
            onNotificationTapped: (n) => tappedNotification = n,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buyer mode: should see buyer + system notifications, not seller ones
      expect(find.text('You were outbid!'), findsOneWidget);
      expect(find.text('Order Shipped'), findsOneWidget);
      expect(find.text('System Maintenance'), findsOneWidget);
      expect(find.text('New Order Received'), findsNothing); // filtered out

      // 2 unread (outbid + shipped; system already read)
      expect(find.text('2 unread'), findsOneWidget);

      // Tap the outbid notification to mark as read
      await tester.tap(find.byKey(const Key('notif-item-0')));
      await tester.pumpAndSettle();

      expect(tappedNotification, isNotNull);
      expect(tappedNotification!.title, 'You were outbid!');
      expect(find.text('1 unread'), findsOneWidget);

      // Tap the shipped notification
      await tester.tap(find.byKey(const Key('notif-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('0 unread'), findsOneWidget);
    });

    qaIntegrationTest(
        'seller workspace shows only seller and system notifications', (
      tester,
    ) async {
      final notifications = [
        _notif(
          id: 'n-1',
          type: NotificationType.outbid,
          audience: NotificationAudience.buyer,
          title: 'You were outbid!',
          body: 'Someone placed a higher bid.',
        ),
        _notif(
          id: 'n-2',
          type: NotificationType.orderConfirmed,
          audience: NotificationAudience.seller,
          title: 'New Order Received',
          body: 'A buyer placed an order.',
        ),
        _notif(
          id: 'n-3',
          type: NotificationType.review,
          audience: NotificationAudience.seller,
          title: 'New Review',
          body: 'A buyer left a 5-star review.',
        ),
        _notif(
          id: 'n-4',
          type: NotificationType.system,
          audience: NotificationAudience.system,
          title: 'System Update',
          body: 'New features available.',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: _NotificationInboxHarness(
            notifications: notifications,
            accountMode: AccountMode.seller,
            hasSellerAccess: true,
            onNotificationTapped: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Seller mode: should see seller + system notifications, not buyer ones
      expect(find.text('You were outbid!'), findsNothing); // filtered
      expect(find.text('New Order Received'), findsOneWidget);
      expect(find.text('New Review'), findsOneWidget);
      expect(find.text('System Update'), findsOneWidget);
      expect(find.text('3 unread'), findsOneWidget);
    });

    qaIntegrationTest(
        'buyer-only user without seller access never sees seller notifications',
        (
      tester,
    ) async {
      final notifications = [
        _notif(
          id: 'n-1',
          type: NotificationType.outbid,
          audience: NotificationAudience.buyer,
          title: 'Buyer Alert',
          body: 'Your bid update.',
        ),
        _notif(
          id: 'n-2',
          type: NotificationType.orderConfirmed,
          audience: NotificationAudience.seller,
          title: 'Seller Alert',
          body: 'New order for you.',
        ),
        _notif(
          id: 'n-3',
          type: NotificationType.system,
          audience: NotificationAudience.system,
          title: 'System Alert',
          body: 'System notice.',
        ),
      ];

      // Even in buyer mode, without seller access, seller notifs must be hidden
      final filtered = notificationsForAccountMode(
        notifications,
        AccountMode.buyer,
        hasSellerAccess: false,
      );

      expect(filtered.length, 2);
      expect(
          filtered.any((n) => n.audience == NotificationAudience.seller), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: _NotificationInboxHarness(
            notifications: notifications,
            accountMode: AccountMode.buyer,
            hasSellerAccess: false,
            onNotificationTapped: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seller Alert'), findsNothing);
      expect(find.text('Buyer Alert'), findsOneWidget);
      expect(find.text('System Alert'), findsOneWidget);
    });

    qaIntegrationTest(
        'NotificationModel.fromJson parses type, audience, and payload', (
      tester,
    ) async {
      final notification = NotificationModel.fromJson({
        'notification_id': 'notif-json-1',
        'user_id': 'user-qa-1',
        'type': 'outbid',
        'audience': 'buyer',
        'title': 'You were outbid!',
        'body': 'Another user placed a higher bid.',
        'created_at': '2026-10-04T14:00:00.000Z',
        'is_read': false,
        'data': {
          'auction_id': 'auc-001',
          'product_id': 'prod-001',
        },
      });

      expect(notification.id, 'notif-json-1');
      expect(notification.type, NotificationType.outbid);
      expect(notification.audience, NotificationAudience.buyer);
      expect(notification.isRead, isFalse);
      expect(notification.data['auction_id'], 'auc-001');

      // Copy with marks as read
      final read = notification.copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.id, notification.id);
    });

    qaIntegrationTest(
        'notificationAppealReportId validates UUID and can_appeal flag', (
      tester,
    ) async {
      // Valid appeal
      expect(
        notificationAppealReportId({
          'can_appeal': 'true',
          'report_id': 'a1b2c3d4-e5f6-1234-abcd-1234567890ab',
        }),
        'a1b2c3d4-e5f6-1234-abcd-1234567890ab',
      );

      // can_appeal is false
      expect(
        notificationAppealReportId({
          'can_appeal': 'false',
          'report_id': 'a1b2c3d4-e5f6-1234-abcd-1234567890ab',
        }),
        isNull,
      );

      // Invalid UUID format
      expect(
        notificationAppealReportId({
          'can_appeal': 'true',
          'report_id': 'not-a-uuid',
        }),
        isNull,
      );

      // Empty report_id
      expect(
        notificationAppealReportId({
          'can_appeal': 'true',
          'report_id': '',
        }),
        isNull,
      );

      // notificationPayload handles non-Map gracefully
      expect(notificationPayload(null), const <String, String>{});
      expect(notificationPayload('not a map'), const <String, String>{});
      expect(
        notificationPayload({'key': 'value', 'count': 42}),
        {'key': 'value', 'count': '42'},
      );
    });

    qaIntegrationTest(
        'notificationAudienceDbValuesForMode returns correct DB filters', (
      tester,
    ) async {
      // Buyer mode with seller access
      expect(
        notificationAudienceDbValuesForMode(
          AccountMode.buyer,
          hasSellerAccess: true,
        ),
        ['buyer', 'system'],
      );

      // Seller mode with seller access
      expect(
        notificationAudienceDbValuesForMode(
          AccountMode.seller,
          hasSellerAccess: true,
        ),
        ['seller', 'system'],
      );

      // Without seller access (always buyer+system regardless of mode)
      expect(
        notificationAudienceDbValuesForMode(
          AccountMode.buyer,
          hasSellerAccess: false,
        ),
        ['buyer', 'system'],
      );
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    notificationIntegrationTests();
  });
}
