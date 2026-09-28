DateTime? chatTimestamptz(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

/// Inbox unread is derived from last_message vs the viewer's last_read column.
/// The sender's last_read is advanced by the insert trigger, so their own
/// send does not appear unread.
int conversationUnreadIndicator({
  required DateTime lastMessageAt,
  DateTime? myLastReadAt,
  String? lastMessage,
}) {
  if (lastMessage == null || lastMessage.trim().isEmpty) return 0;
  if (myLastReadAt == null) return 1;
  return lastMessageAt.toUtc().isAfter(myLastReadAt.toUtc()) ? 1 : 0;
}

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
    this.otherUserId,
    this.otherName,
    this.otherAvatar,
    this.lastReadAtA,
    this.lastReadAtB,
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
  final String? otherUserId;
  final String? otherName;
  final String? otherAvatar;
  final DateTime? lastReadAtA;
  final DateTime? lastReadAtB;

  bool get hasUnread => unreadCount > 0;

  String titleFor(String myId) {
    if (otherName != null && otherName!.isNotEmpty) return otherName!;
    final index = participantIds.indexOf(myId);
    if (index >= 0 && participantNames.length > (index == 0 ? 1 : 0)) {
      return participantNames[index == 0 ? 1 : 0];
    }
    return participantNames.isNotEmpty ? participantNames.first : 'Chat';
  }

  String avatarFor(String myId) {
    if (otherAvatar != null) return otherAvatar!;
    final index = participantIds.indexOf(myId);
    if (index >= 0 && participantAvatars.length > (index == 0 ? 1 : 0)) {
      return participantAvatars[index == 0 ? 1 : 0];
    }
    return participantAvatars.isNotEmpty ? participantAvatars.first : '';
  }

  factory ChatModel.fromSupabase(
    Map<String, dynamic> row, {
    required String myId,
    Map<String, dynamic>? other,
    Map<String, dynamic>? product,
  }) {
    final a = row['participant_a'] as String? ?? '';
    final b = row['participant_b'] as String? ?? '';
    final otherId = a == myId ? b : a;
    final name =
        other?['full_name'] as String? ??
        other?['username'] as String? ??
        'User';
    final avatar = other?['avatar'] as String? ?? '';
    final lastReadAtA = chatTimestamptz(row['last_read_at_a']);
    final lastReadAtB = chatTimestamptz(row['last_read_at_b']);
    final lastMessageAt =
        chatTimestamptz(row['last_message_at']) ?? DateTime.now().toUtc();
    final lastMessage = row['last_message'] as String? ?? '';
    final myLastReadAt = myId == a ? lastReadAtA : lastReadAtB;
    final productRow =
        product ??
        (row['product'] is Map<String, dynamic>
            ? row['product'] as Map<String, dynamic>
            : null);
    return ChatModel(
      id: row['conversation_id'] as String? ?? '',
      participantIds: [a, b],
      participantNames: [name, name],
      participantAvatars: [avatar, avatar],
      productId:
          row['product_id'] as String? ?? productRow?['product_id'] as String?,
      productTitle:
          productRow?['name'] as String? ?? productRow?['title'] as String?,
      productImage: productRow?['image_url'] as String?,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      unreadCount: conversationUnreadIndicator(
        lastMessageAt: lastMessageAt,
        myLastReadAt: myLastReadAt,
        lastMessage: lastMessage,
      ),
      otherUserId: otherId,
      otherName: name,
      otherAvatar: avatar,
      lastReadAtA: lastReadAtA,
      lastReadAtB: lastReadAtB,
    );
  }
}
