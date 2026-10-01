import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/review_model.dart';
import '../../buyer/data/order_query.dart';
import 'review_photo_upload.dart';

const _reviewSelect =
    '*, review_photos(review_photo_id, file_path, display_order, created_at)';

Future<Map<String, ReviewModel>> fetchMyReviewsForOrders(
  SupabaseService supabase,
  String reviewerId,
  Iterable<String> orderIds,
) async {
  final ids = orderIds.where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty || reviewerId.isEmpty) return {};

  try {
    final rows = await supabase.client
        .from('reviews')
        .select(_reviewSelect)
        .eq('reviewer_id', reviewerId)
        .inFilter('order_id', ids);

    final out = <String, ReviewModel>{};
    for (final raw in rows as List<dynamic>) {
      final review = _withPhotoUrls(
        supabase,
        ReviewModel.fromSupabase(raw as Map<String, dynamic>),
      );
      if (review.orderId.isNotEmpty) {
        out[review.orderId] = review;
      }
    }
    return out;
  } catch (e) {
    debugPrint('fetchMyReviewsForOrders error: $e');
    return {};
  }
}

Future<List<ReviewModel>> fetchReviewsForUser(
  SupabaseService supabase,
  String reviewedUserId, {
  int limit = 30,
}) async {
  if (reviewedUserId.isEmpty) return [];

  try {
    final rows = await supabase.client
        .from('reviews')
        .select(_reviewSelect)
        .eq('reviewed_user_id', reviewedUserId)
        .order('created_at', ascending: false)
        .limit(limit);

    final reviews = (rows as List<dynamic>)
        .map(
          (raw) => _withPhotoUrls(
            supabase,
            ReviewModel.fromSupabase(raw as Map<String, dynamic>),
          ),
        )
        .toList();

    final reviewerIds = reviews.map((review) => review.reviewerId).toSet();
    final profiles = await loadPublicProfiles(supabase, reviewerIds);

    return reviews.map((review) {
      final profile = profiles[review.reviewerId];
      if (profile == null) return review;
      return ReviewModel.fromSupabase({
        'review_id': review.id,
        'order_id': review.orderId,
        'reviewer_id': review.reviewerId,
        'reviewed_user_id': review.reviewedUserId,
        'rating': review.rating,
        'review_text': review.comment,
        'review_type': review.reviewType,
        'created_at': review.createdAt.toIso8601String(),
        'reviewer': profile,
      });
    }).toList();
  } catch (e) {
    debugPrint('fetchReviewsForUser error: $e');
    return [];
  }
}

ReviewModel _withPhotoUrls(SupabaseService supabase, ReviewModel review) {
  if (review.photos.isEmpty) return review;
  final photos = review.photos
      .map(
        (p) =>
            p.copyWith(publicUrl: reviewPhotoPublicUrl(supabase, p.filePath)),
      )
      .toList();
  return review.copyWith(photos: photos);
}

Future<List<ReviewModel>> fetchMyBuyerToSellerReviews(
  SupabaseService supabase,
  String reviewerId,
) async {
  if (reviewerId.isEmpty) return [];

  try {
    final rows = await supabase.client
        .from('reviews')
        .select(_reviewSelect)
        .eq('reviewer_id', reviewerId)
        .eq('review_type', 'buyer_to_seller')
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .map(
          (raw) => _withPhotoUrls(
            supabase,
            ReviewModel.fromSupabase(raw as Map<String, dynamic>),
          ),
        )
        .toList();
  } catch (e) {
    debugPrint('fetchMyBuyerToSellerReviews error: $e');
    return [];
  }
}
