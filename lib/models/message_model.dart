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
    this.productId,
    this.productName,
    this.productPrice,
    this.productImageUrl,
    this.productStatus,
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
  final String? productId;
  final String? productName;
  final double? productPrice;
  final String? productImageUrl;
  final String? productStatus;
  final String? attachmentPath;

  bool get productShareAvailable =>
      productId != null &&
      productId!.isNotEmpty &&
      (productStatus == null || productStatus == 'active');

  bool isSentBy(String userId) => senderId == userId;

  factory MessageModel.fromSupabase(Map<String, dynamic> row) {
    final post = row['looking_for_post'] as Map<String, dynamic>?;
    final product = row['product'] as Map<String, dynamic>?;
    String? primaryImage;
    if (product != null) {
      final images = product['images'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        Map<String, dynamic>? pick;
        for (final raw in images) {
          final map = raw as Map<String, dynamic>;
          if (map['is_primary'] == true) {
            pick = map;
            break;
          }
          pick ??= map;
        }
        primaryImage = pick?['image_url'] as String?;
      }
      primaryImage ??= product['image_url'] as String?;
    }
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
      productId:
          row['product_id'] as String? ?? product?['product_id'] as String?,
      productName: product?['name'] as String?,
      productPrice: (product?['price'] as num?)?.toDouble(),
      productImageUrl: primaryImage,
      productStatus: product?['status'] as String?,
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
