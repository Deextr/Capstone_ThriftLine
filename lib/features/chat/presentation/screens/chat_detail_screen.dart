import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final userId = auth.user?.id ?? 'buyer_maya';
    final messages = data.messagesFor(widget.chatId);
    final chat = data.chatsFor(userId).where((c) => c.id == widget.chatId).firstOrNull;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(chat?.participantNames.firstWhere((n) => true) ?? 'Chat'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          actions: [
            IconButton(
              icon: const Icon(Icons.local_offer_outlined),
              onPressed: () => _showOfferSheet(context, userId),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (chat?.productTitle != null)
                ThriftCard(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: chat!.productImage ?? '', 
                          width: 40, 
                          height: 40, 
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: AppColors.surfaceVariant),
                          errorWidget: (_, _, _) => Container(color: AppColors.surfaceVariant, child: const Icon(Icons.image_outlined, size: 20)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(chat.productTitle!, style: AppTypography.caption)),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final isSent = msg.isSentBy(userId);
                    return Align(
                      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isSent ? AppColors.primary : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (msg.type == MessageType.offer)
                              Text('Offer: ${formatCurrency(msg.offerAmount ?? 0)}', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSent ? Colors.white : AppColors.secondary)),
                            Text(msg.content, style: AppTypography.body.copyWith(color: isSent ? Colors.white : AppColors.textPrimary)),
                            Text(formatRelativeTime(msg.createdAt), style: AppTypography.caption.copyWith(color: isSent ? Colors.white70 : AppColors.textHint, fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.image_outlined), onPressed: () => showThriftSnackBar(context, 'Image attachment coming soon')),
                    Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Type a message...', border: OutlineInputBorder()))),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.primary),
                      onPressed: () {
                        if (_controller.text.trim().isEmpty) return;
                        data.sendMessage(chatId: widget.chatId, senderId: userId, content: _controller.text.trim());
                        _controller.clear();
                      },
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

  void _showOfferSheet(BuildContext context, String userId) {
    final priceCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    ThriftBottomSheet.show(
      context,
      title: 'Send Offer',
      child: Column(
        children: [
          ThriftTextField(label: 'Price', controller: priceCtrl, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          ThriftTextField(label: 'Message', controller: msgCtrl),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Send Offer',
            variant: ThriftButtonVariant.secondary,
            onPressed: () {
              context.read<DataProvider>().sendMessage(
                chatId: widget.chatId,
                senderId: userId,
                content: msgCtrl.text.isEmpty ? 'Sent an offer' : msgCtrl.text,
                type: MessageType.offer,
                offerAmount: double.tryParse(priceCtrl.text),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
