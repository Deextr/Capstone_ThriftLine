class ChatModel {
  const ChatModel({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.participantAvatars,
    this.productId,
    this.productTitle,
    this.productImage,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final List<String> participantIds;
  final List<String> participantNames;
  final List<String> participantAvatars;
  final String? productId;
  final String? productTitle;
  final String? productImage;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
}
