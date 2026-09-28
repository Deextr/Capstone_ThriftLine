import 'enums.dart';

class MessageModel {
  const MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.type = MessageType.text,
    this.isRead = false,
    this.offerAmount,
    this.lookingForPostId,
    this.lookingForTitle,
    this.lookingForImageUrl,
    this.attachmentPath,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final MessageType type;
  final bool isRead;
  final double? offerAmount;
  final String? lookingForPostId;
  final String? lookingForTitle;
  final String? lookingForImageUrl;
  final String? attachmentPath;

  bool isSentBy(String userId) => senderId == userId;

  factory MessageModel.fromSupabase(Map<String, dynamic> row) {
    final post = row['looking_for_post'] as Map<String, dynamic>?;
    return MessageModel(
      id: row['message_id'] as String? ?? '',
      chatId: row['conversation_id'] as String? ?? '',
      senderId: row['sender_id'] as String? ?? '',
      content: row['content'] as String? ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      type: MessageType.fromString(row['message_type'] as String? ?? 'text'),
      offerAmount: (row['offer_amount'] as num?)?.toDouble(),
      lookingForPostId:
          row['looking_for_post_id'] as String? ?? post?['post_id'] as String?,
      lookingForTitle: post?['title'] as String?,
      lookingForImageUrl: post?['reference_image_url'] as String?,
      attachmentPath:
          (row['attachment_path'] as String?)?.trim().isNotEmpty == true
          ? row['attachment_path'] as String
          : (row['message_type'] == 'image' &&
                    (row['content'] as String?)?.contains('/') == true
                ? row['content'] as String
                : null),
    );
  }
}
