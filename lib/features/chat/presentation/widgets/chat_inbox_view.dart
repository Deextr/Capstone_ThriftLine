import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/chat_list_controller.dart';

/// Shared inbox body used by the Messages tabs and the `/chat` route.
class ChatInboxView extends StatelessWidget {
  const ChatInboxView({super.key, this.showHeader = false});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatListController>();
    final chats = controller.chats;

    Widget body;
    if (controller.isLoading && chats.isEmpty) {
      body = const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    } else if (controller.errorMessage != null && chats.isEmpty) {
      body = ErrorState(
        message: controller.errorMessage!,
        onRetry: controller.load,
      );
    } else if (chats.isEmpty) {
      body = const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet',
        message:
            'When you chat with a seller or buyer, the thread shows up here.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: controller.load,
        color: AppColors.primary,
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: chats.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final chat = chats[i];
            final unread = chat.hasUnread;
            return ListTile(
              leading: ThriftAvatar(imageUrl: chat.otherAvatar ?? '', size: 48),
              title: Text(
                chat.otherName ?? 'Chat',
                style: AppTypography.body.copyWith(
                  fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chat.productTitle != null &&
                      chat.productTitle!.trim().isNotEmpty)
                    Text(
                      chat.productTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    chat.lastMessage.isEmpty
                        ? 'No messages yet'
                        : chat.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      color: unread
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              isThreeLine:
                  chat.productTitle != null &&
                  chat.productTitle!.trim().isNotEmpty,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRelativeTime(chat.lastMessageAt),
                    style: AppTypography.caption.copyWith(
                      color: unread ? AppColors.primary : AppColors.textHint,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => context.push(RouteNames.chatThread(chat.id)),
            );
          },
        ),
      );
    }

    if (!showHeader) return body;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Messages', style: AppTypography.heading),
                const SizedBox(height: 4),
                Text('Your conversations', style: AppTypography.caption),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
