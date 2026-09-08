import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/chat_list_controller.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatListController>();
    final chats = controller.chats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : controller.errorMessage != null
            ? ErrorState(
                message: controller.errorMessage!,
                onRetry: controller.load,
              )
            : chats.isEmpty
            ? const Center(child: Text('No conversations yet'))
            : RefreshIndicator(
                onRefresh: controller.load,
                color: AppColors.primary,
                child: ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (_, i) {
                    final chat = chats[i];
                    return ListTile(
                      leading: ThriftAvatar(
                        imageUrl: chat.otherAvatar ?? '',
                        size: 48,
                      ),
                      title: Text(
                        chat.otherName ?? 'Chat',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        chat.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        formatRelativeTime(chat.lastMessageAt),
                        style: AppTypography.caption,
                      ),
                      onTap: () => context.push('/chat/${chat.id}'),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
