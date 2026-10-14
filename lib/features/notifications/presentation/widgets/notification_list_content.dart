import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/notification_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/notifications_provider.dart';
import '../../domain/notification_catalog.dart';
import '../../domain/notification_navigation.dart';

class NotificationListContent extends StatelessWidget {
  const NotificationListContent({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<NotificationModel> items;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();

    if (provider.loadError != null && items.isEmpty) {
      return _ErrorState(
        message: provider.loadError!,
        onRetry: provider.refresh,
      );
    }

    if (items.isEmpty) {
      return _EmptyState(title: emptyTitle, subtitle: emptySubtitle);
    }

    final groups = groupNotificationsByDay(items, DateTime.now());

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: provider.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMd,
          AppConstants.spacingSm,
          AppConstants.spacingMd,
          AppConstants.spacingLg,
        ),
        itemCount: groups.length,
        itemBuilder: (context, sectionIndex) {
          final section = groups[sectionIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: AppConstants.spacingSm,
                  bottom: AppConstants.spacingSm,
                ),
                child: Text(
                  section.label,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              ...section.items.map(
                (n) => _NotificationTile(
                  notification: n,
                  onTap: () {
                    context.read<NotificationsProvider>().markRead(n.id);
                    openNotification(
                      GoRouter.of(context),
                      notification: n,
                      activeAccount: context.read<AuthProvider>().activeAccount,
                    );
                  },
                  onMarkRead: n.isRead
                      ? null
                      : () => context.read<NotificationsProvider>().markRead(
                          n.id,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onMarkRead,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final accent = notificationAccent(notification.type);
    final icon = notificationIcon(notification.type);

    return Material(
      color: notification.isRead
          ? AppColors.surface
          : AppColors.primary.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: notification.isRead
                  ? AppColors.border.withValues(alpha: 0.6)
                  : AppColors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: AppTypography.body.copyWith(
                              fontWeight: notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          formatRelativeTime(notification.createdAt),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                        if (onMarkRead != null) ...[
                          const Spacer(),
                          TextButton(
                            onPressed: onMarkRead,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Mark read',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 56,
              color: AppColors.textHint.withValues(alpha: 0.8),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              title,
              style: AppTypography.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.error),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              'Could not load notifications',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingMd),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
