import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/notification_model.dart';
import '../../../../providers/notifications_provider.dart';
import '../../domain/notification_catalog.dart';
import '../widgets/notification_list_content.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _tabs = ['all', 'orders', 'bids', 'messages', 'system'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<NotificationModel> _itemsForTab(NotificationsProvider provider, String tab) {
    final visible = provider.items;
    if (tab == 'all') return visible;
    return visible.where((n) => notificationMatchesTab(n, tab)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationsProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (notifications.unreadCount > 0)
            TextButton(
              onPressed: notifications.isLoading ? null : notifications.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Orders'),
            Tab(text: 'Bids'),
            Tab(text: 'Messages'),
            Tab(text: 'System'),
          ],
        ),
      ),
      body: SafeArea(
        child: notifications.isLoading && notifications.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tab,
                children: [
                  for (final tab in _tabs)
                    NotificationListContent(
                      items: _itemsForTab(notifications, tab),
                      emptyTitle: _emptyTitle(tab),
                      emptySubtitle: _emptySubtitle(tab),
                    ),
                ],
              ),
      ),
    );
  }

  String _emptyTitle(String tab) => switch (tab) {
    'orders' => 'No order updates yet',
    'bids' => 'No bidding alerts',
    'messages' => 'No message alerts',
    'system' => 'No account updates',
    _ => 'You are all caught up',
  };

  String _emptySubtitle(String tab) => switch (tab) {
    'orders' =>
      'Payments, shipping, and delivery notices for your workspace will show here.',
    'bids' => 'Outbid and auction results will appear here when they happen.',
    'messages' =>
      'When someone messages you, a alert will show up here and in Chat.',
    'system' =>
      'Verification, reports, and marketplace policy updates appear here.',
    _ => 'New alerts about your buys, sells, and account will land here.',
  };
}
