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
  });

  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final MessageType type;
  final bool isRead;
  final double? offerAmount;

  bool isSentBy(String userId) => senderId == userId;
}
