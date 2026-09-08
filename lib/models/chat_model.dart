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
  }) {
    final a = row['participant_a'] as String? ?? '';
    final b = row['participant_b'] as String? ?? '';
    final otherId = a == myId ? b : a;
    final name =
        other?['full_name'] as String? ??
        other?['username'] as String? ??
        'User';
    final avatar = other?['avatar'] as String? ?? '';
    return ChatModel(
      id: row['conversation_id'] as String? ?? '',
      participantIds: [a, b],
      participantNames: [name, name],
      participantAvatars: [avatar, avatar],
      lastMessage: row['last_message'] as String? ?? '',
      lastMessageAt: row['last_message_at'] != null
          ? DateTime.parse(row['last_message_at'] as String)
          : DateTime.now(),
      otherUserId: otherId,
      otherName: name,
      otherAvatar: avatar,
    );
  }
}
