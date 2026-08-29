import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/notification_model.dart';
import '../../../../providers/notifications_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: notifications.markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            TabBar(
              controller: _tab,
              isScrollable: true,
              labelColor: AppColors.primary,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Orders'),
                Tab(text: 'Bids'),
                Tab(text: 'Messages'),
                Tab(text: 'System'),
              ],
            ),
            Expanded(
              child: notifications.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _list(notifications.items),
                        _list(notifications.forTab('orders')),
                        _list(notifications.forTab('bids')),
                        _list(notifications.forTab('messages')),
                        _list(notifications.forTab('system')),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<NotificationModel> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No notifications'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final n = items[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _colorFor(n.type).withValues(alpha: 0.15),
            child: Text(_emojiFor(n.type), style: const TextStyle(fontSize: 18)),
          ),
          title: Text(
            n.title,
            style: AppTypography.body.copyWith(
              fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
          subtitle: Text(n.body, style: AppTypography.caption),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(formatRelativeTime(n.createdAt), style: AppTypography.caption),
              if (!n.isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          onTap: () => context.read<NotificationsProvider>().markRead(n.id),
        );
      },
    );
  }

  String _emojiFor(NotificationType type) => switch (type) {
        NotificationType.outbid => '🎯',
        NotificationType.wonBid => '🏆',
        NotificationType.shipped => '📦',
        NotificationType.message => '💬',
        NotificationType.saved => '❤️',
        NotificationType.orderConfirmed => '✅',
        NotificationType.verificationSubmitted => '📄',
        NotificationType.verificationApproved => '✅',
        NotificationType.verificationRejected => '⚠️',
        NotificationType.system => 'ℹ️',
      };

  Color _colorFor(NotificationType type) => switch (type) {
        NotificationType.outbid => AppColors.secondary,
        NotificationType.wonBid => AppColors.primary,
        NotificationType.shipped => AppColors.info,
        NotificationType.message => AppColors.textSecondary,
        NotificationType.saved => const Color(0xFFEC4899),
        NotificationType.orderConfirmed => AppColors.success,
        NotificationType.verificationSubmitted => AppColors.warning,
        NotificationType.verificationApproved => AppColors.success,
        NotificationType.verificationRejected => AppColors.error,
        NotificationType.system => AppColors.textHint,
      };
}
