import 'enums.dart';

class LookingForModel {
  const LookingForModel({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.buyerAvatar,
    required this.title,
    required this.description,
    required this.category,
    required this.budgetMin,
    required this.budgetMax,
    this.size,
    required this.location,
    required this.createdAt,
    this.responseCount = 0,
    this.status = LookingForStatus.active,
    this.thumbnailUrl,
    this.likesCount = 0,
    this.sharesCount = 0,
    this.isLiked = false,
  });

  final String id;
  final String buyerId;
  final String buyerName;
  final String buyerAvatar;
  final String title;
  final String description;
  final ProductCategory category;
  final double budgetMin;
  final double budgetMax;
  final String? size;
  final String location;
  final DateTime createdAt;
  final int responseCount;
  final LookingForStatus status;
  final String? thumbnailUrl;
  final int likesCount;
  final int sharesCount;
  final bool isLiked;

  factory LookingForModel.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? buyer,
  }) {
    final statusRaw = row['status'] as String? ?? 'open';
    final status = switch (statusRaw) {
      'fulfilled' => LookingForStatus.fulfilled,
      'closed' => LookingForStatus.closed,
      _ => LookingForStatus.active,
    };
    final buyerName =
        buyer?['full_name'] as String? ??
        buyer?['username'] as String? ??
        'Buyer';
    final buyerAvatar = buyer?['avatar'] as String? ?? '';
    final categoryName =
        (row['category'] as Map<String, dynamic>?)?['category_name']
            as String? ??
        '';

    return LookingForModel(
      id: row['post_id'] as String? ?? '',
      buyerId: row['user_id'] as String? ?? '',
      buyerName: buyerName,
      buyerAvatar: buyerAvatar,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      category: ProductCategory.fromString(categoryName),
      budgetMin: (row['minimum_price'] as num?)?.toDouble() ?? 0,
      budgetMax: (row['maximum_price'] as num?)?.toDouble() ?? 0,
      size: row['preferred_size'] as String?,
      location: row['location'] as String? ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      responseCount: (row['response_count'] as num?)?.toInt() ?? 0,
      status: status,
      thumbnailUrl: row['reference_image_url'] as String?,
    );
  }

  LookingForModel copyWith({
    String? id,
    String? buyerId,
    String? buyerName,
    String? buyerAvatar,
    String? title,
    String? description,
    ProductCategory? category,
    double? budgetMin,
    double? budgetMax,
    String? size,
    String? location,
    DateTime? createdAt,
    int? responseCount,
    LookingForStatus? status,
    String? thumbnailUrl,
    int? likesCount,
    int? sharesCount,
    bool? isLiked,
  }) {
    return LookingForModel(
      id: id ?? this.id,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      buyerAvatar: buyerAvatar ?? this.buyerAvatar,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      size: size ?? this.size,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      responseCount: responseCount ?? this.responseCount,
      status: status ?? this.status,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      likesCount: likesCount ?? this.likesCount,
      sharesCount: sharesCount ?? this.sharesCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

class LookingForResponse {
  const LookingForResponse({
    required this.id,
    required this.postId,
    required this.sellerId,
    required this.message,
    required this.createdAt,
    required this.sellerName,
    this.sellerAvatar,
  });

  final String id;
  final String postId;
  final String sellerId;
  final String message;
  final DateTime createdAt;
  final String sellerName;
  final String? sellerAvatar;

  factory LookingForResponse.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? seller,
  }) {
    return LookingForResponse(
      id: row['response_id'] as String? ?? '',
      postId: row['post_id'] as String? ?? '',
      sellerId: row['seller_id'] as String? ?? '',
      message: row['message'] as String? ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      sellerName:
          seller?['full_name'] as String? ??
          seller?['username'] as String? ??
          'Seller',
      sellerAvatar: seller?['avatar'] as String?,
    );
  }
}
