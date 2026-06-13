import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final userId = auth.user?.id ?? 'buyer_maya';
    final chats = data.chatsFor(userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: chats.isEmpty
            ? const Center(child: Text('No conversations yet'))
            : ListView.builder(
                itemCount: chats.length,
                itemBuilder: (_, i) {
                  final chat = chats[i];
                  final otherIndex = chat.participantIds.indexOf(userId) == 0 ? 1 : 0;
                  return ListTile(
                    leading: ThriftAvatar(imageUrl: chat.participantAvatars[otherIndex], size: 48, showOnline: true),
                    title: Text(chat.participantNames[otherIndex], style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(chat.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatRelativeTime(chat.lastMessageAt), style: AppTypography.caption),
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: Text('${chat.unreadCount}', style: AppTypography.caption.copyWith(color: Colors.white, fontSize: 10)),
                          ),
                      ],
                    ),
                    onTap: () => context.push('/chat/${chat.id}'),
                  );
                },
              ),
      ),
    );
  }
}
