import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/notification_model.dart';

/// Tab filters aligned with backend notification types and payloads.
bool notificationMatchesTab(NotificationModel n, String tab) {
  return switch (tab) {
    'orders' => _isOrderRelated(n),
    'bids' =>
      n.type == NotificationType.outbid ||
      n.type == NotificationType.wonBid ||
      _hasNonEmpty(n.data['auction_id']),
    'messages' => n.type == NotificationType.message,
    'system' => _isSystemTab(n),
    _ => true,
  };
}

bool _isOrderRelated(NotificationModel n) {
  if (n.type == NotificationType.shipped ||
      n.type == NotificationType.orderConfirmed) {
    return true;
  }
  if (!_hasNonEmpty(n.data['order_id'])) return false;
  return n.type != NotificationType.outbid && n.type != NotificationType.wonBid;
}

bool _isSystemTab(NotificationModel n) {
  if (_isOrderRelated(n) ||
      n.type == NotificationType.message ||
      n.type == NotificationType.outbid ||
      n.type == NotificationType.wonBid) {
    return false;
  }
  return true;
}

bool _hasNonEmpty(String? value) =>
    value != null && value.trim().isNotEmpty;

IconData notificationIcon(NotificationType type) => switch (type) {
  NotificationType.outbid => Icons.gavel_outlined,
  NotificationType.wonBid => Icons.emoji_events_outlined,
  NotificationType.shipped => Icons.local_shipping_outlined,
  NotificationType.message => Icons.chat_bubble_outline_rounded,
  NotificationType.saved => Icons.favorite_border_rounded,
  NotificationType.orderConfirmed => Icons.receipt_long_outlined,
  NotificationType.verificationSubmitted => Icons.description_outlined,
  NotificationType.verificationApproved => Icons.verified_outlined,
  NotificationType.verificationRejected => Icons.warning_amber_rounded,
  NotificationType.review => Icons.star_outline_rounded,
  NotificationType.reportDecision => Icons.shield_outlined,
  NotificationType.system => Icons.notifications_none_outlined,
};

Color notificationAccent(NotificationType type) => switch (type) {
  NotificationType.outbid => AppColors.secondary,
  NotificationType.wonBid => AppColors.primary,
  NotificationType.shipped => AppColors.info,
  NotificationType.message => AppColors.textSecondary,
  NotificationType.saved => const Color(0xFFEC4899),
  NotificationType.orderConfirmed => AppColors.success,
  NotificationType.verificationSubmitted => AppColors.warning,
  NotificationType.verificationApproved => AppColors.success,
  NotificationType.verificationRejected => AppColors.error,
  NotificationType.review => AppColors.warning,
  NotificationType.reportDecision => AppColors.info,
  NotificationType.system => AppColors.textHint,
};

String notificationSectionLabel(DateTime createdAt, DateTime now) {
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return 'Earlier';
}

List<({String label, List<NotificationModel> items})> groupNotificationsByDay(
  List<NotificationModel> items,
  DateTime now,
) {
  if (items.isEmpty) return const [];
  final buckets = <String, List<NotificationModel>>{};
  final order = <String>[];
  for (final n in items) {
    final label = notificationSectionLabel(n.createdAt, now);
    if (!buckets.containsKey(label)) {
      buckets[label] = [];
      order.add(label);
    }
    buckets[label]!.add(n);
  }
  return [
    for (final label in order) (label: label, items: buckets[label]!),
  ];
}
