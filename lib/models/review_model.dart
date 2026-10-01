import 'base_model.dart';

class ReviewPhoto {
  const ReviewPhoto({required this.id, required this.filePath, this.publicUrl});

  final String id;
  final String filePath;
  final String? publicUrl;

  ReviewPhoto copyWith({String? publicUrl}) {
    return ReviewPhoto(
      id: id,
      filePath: filePath,
      publicUrl: publicUrl ?? this.publicUrl,
    );
  }

  factory ReviewPhoto.fromSupabase(Map<String, dynamic> row) {
    return ReviewPhoto(
      id: row['review_photo_id'] as String? ?? '',
      filePath: row['file_path'] as String? ?? '',
    );
  }
}

/// Represents a review left by a buyer or seller on an order.
/// Maps directly to the Supabase `reviews` table.
class ReviewModel extends BaseModel {
  const ReviewModel({
    required this.id,
    required this.orderId,
    required this.reviewerId,
    required this.reviewerName,
    required this.reviewerUsername,
    required this.reviewerAvatar,
    required this.reviewedUserId,
    required this.rating,
    required this.comment,
    required this.reviewType,
    required this.createdAt,
    this.photos = const [],
  });

  final String id;
  final String orderId;
  final String reviewerId;
  final String reviewerName;
  final String reviewerUsername;
  final String reviewerAvatar;
  final String reviewedUserId;
  final int rating;
  final String comment;
  final String reviewType;
  final DateTime createdAt;
  final List<ReviewPhoto> photos;

  factory ReviewModel.fromSupabase(Map<String, dynamic> row) {
    final reviewer =
        (row['reviewer'] ?? row['user_public_profiles'] ?? row['users'])
            as Map<String, dynamic>?;

    final reviewerUsername = reviewer?['username'] as String? ?? '';
    final reviewerName =
        reviewer?['full_name'] as String? ??
        (reviewerUsername.isNotEmpty ? reviewerUsername : 'Buyer');
    final reviewerAvatar =
        reviewer?['avatar'] as String? ??
        'https://ui-avatars.com/api/?name=${Uri.encodeComponent(reviewerName)}&background=0D9488&color=fff&size=150';

    final photoRows = row['review_photos'] as List<dynamic>? ?? const [];
    final photos =
        photoRows
            .map((p) => ReviewPhoto.fromSupabase(p as Map<String, dynamic>))
            .where((p) => p.filePath.isNotEmpty)
            .toList()
          ..sort((a, b) => a.filePath.compareTo(b.filePath));

    return ReviewModel(
      id: row['review_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      reviewerId: row['reviewer_id'] as String? ?? '',
      reviewerName: reviewerName,
      reviewerUsername: reviewerUsername,
      reviewerAvatar: reviewerAvatar,
      reviewedUserId: row['reviewed_user_id'] as String? ?? '',
      rating: (row['rating'] as num?)?.toInt() ?? 5,
      comment: row['review_text'] as String? ?? '',
      reviewType: row['review_type'] as String? ?? 'buyer_to_seller',
      createdAt: row['created_at'] != null
          ? (DateTime.tryParse(row['created_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      photos: photos,
    );
  }

  ReviewModel copyWith({List<ReviewPhoto>? photos}) {
    return ReviewModel(
      id: id,
      orderId: orderId,
      reviewerId: reviewerId,
      reviewerName: reviewerName,
      reviewerUsername: reviewerUsername,
      reviewerAvatar: reviewerAvatar,
      reviewedUserId: reviewedUserId,
      rating: rating,
      comment: comment,
      reviewType: reviewType,
      createdAt: createdAt,
      photos: photos ?? this.photos,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'review_id': id,
    'order_id': orderId,
    'reviewer_id': reviewerId,
    'reviewer_name': reviewerName,
    'reviewer_username': reviewerUsername,
    'reviewer_avatar': reviewerAvatar,
    'reviewed_user_id': reviewedUserId,
    'rating': rating,
    'review_text': comment,
    'review_type': reviewType,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
