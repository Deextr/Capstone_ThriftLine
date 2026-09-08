import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/message_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/chat_detail_controller.dart';

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
    final chat = context.watch<ChatDetailController>();
    final userId = chat.myId ?? '';
    final messages = chat.messages;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(chat.chat?.titleFor(userId) ?? 'Chat'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.local_offer_outlined),
              onPressed: () => _showOfferSheet(context),
            ),
          ],
        ),
        body: SafeArea(
          child: chat.isLoading && messages.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final msg = messages[i];
                          final isSent = msg.isSentBy(userId);
                          return Align(
                            alignment: isSent
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isSent
                                    ? AppColors.primary
                                    : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: _MessageBody(message: msg, isSent: isSent),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.image_outlined),
                            onPressed: () => showThriftSnackBar(
                              context,
                              'Image attachment coming soon',
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: AppColors.primary,
                            ),
                            onPressed: chat.isSending
                                ? null
                                : () async {
                                    final text = _controller.text;
                                    _controller.clear();
                                    final error = await context
                                        .read<ChatDetailController>()
                                        .sendText(text);
                                    if (!context.mounted || error == null) {
                                      return;
                                    }
                                    showThriftSnackBar(
                                      context,
                                      error,
                                      isError: true,
                                    );
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

  void _showOfferSheet(BuildContext context) {
    final priceCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    ThriftBottomSheet.show(
      context,
      title: 'Send Offer',
      child: Column(
        children: [
          ThriftTextField(
            label: 'Price',
            controller: priceCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          ThriftTextField(label: 'Message', controller: msgCtrl),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Send Offer',
            variant: ThriftButtonVariant.secondary,
            onPressed: () async {
              final amount = double.tryParse(priceCtrl.text);
              if (amount == null) return;
              final error = await context
                  .read<ChatDetailController>()
                  .sendOffer(amount: amount, note: msgCtrl.text);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (error != null) {
                showThriftSnackBar(context, error, isError: true);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message, required this.isSent});

  final MessageModel message;
  final bool isSent;

  @override
  Widget build(BuildContext context) {
    final textColor = isSent ? Colors.white : AppColors.textPrimary;
    final hintColor = isSent ? Colors.white70 : AppColors.textHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.type == MessageType.offer)
          Text(
            'Offer: ${formatCurrency(message.offerAmount ?? 0)}',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: isSent ? Colors.white : AppColors.secondary,
            ),
          ),
        Text(
          message.content,
          style: AppTypography.body.copyWith(color: textColor),
        ),
        if (message.type == MessageType.lookingFor &&
            message.lookingForPostId != null) ...[
          const SizedBox(height: 8),
          if (message.lookingForTitle != null)
            Text(
              message.lookingForTitle!,
              style: AppTypography.caption.copyWith(
                color: hintColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: textColor,
              side: BorderSide(color: hintColor),
            ),
            onPressed: () => context.push(
              RouteNames.lookingForPost(message.lookingForPostId!),
            ),
            child: const Text('View Looking For Request'),
          ),
        ],
        Text(
          formatRelativeTime(message.createdAt),
          style: AppTypography.caption.copyWith(color: hintColor, fontSize: 10),
        ),
      ],
    );
  }
}
