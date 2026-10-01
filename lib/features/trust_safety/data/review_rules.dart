import '../../../models/review_model.dart';

const Duration kReviewEditWindow = Duration(hours: 24);
const int kReviewCommentMaxLength = 1000;
const int kReviewRatingMin = 1;
const int kReviewRatingMax = 5;
const int kReviewPhotoMaxCount = 3;

enum ReviewActionKind { leave, edit, view }

bool canEditReview(DateTime createdAt, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  return clock.isBefore(createdAt.add(kReviewEditWindow));
}

ReviewActionKind reviewActionKind(ReviewModel? existing, {DateTime? now}) {
  if (existing == null) return ReviewActionKind.leave;
  if (canEditReview(existing.createdAt, now: now)) {
    return ReviewActionKind.edit;
  }
  return ReviewActionKind.view;
}

String reviewActionLabel(ReviewActionKind kind, {required bool ratingBuyer}) {
  return switch (kind) {
    ReviewActionKind.leave => ratingBuyer ? 'Rate Buyer' : 'Leave a Review',
    ReviewActionKind.edit => 'Edit Review',
    ReviewActionKind.view => 'View Review',
  };
}

String reviewPrompt({required bool ratingBuyer}) {
  return ratingBuyer
      ? 'How was your experience with this buyer?'
      : 'How was your experience with this seller?';
}

String formatRatingAverage({
  double? average,
  int count = 0,
  bool compact = false,
}) {
  if (count <= 0) return compact ? '—' : 'No reviews yet';
  final value = average ?? 0;
  return value.toStringAsFixed(1);
}

String? reviewRatingError(int rating) {
  if (rating < kReviewRatingMin || rating > kReviewRatingMax) {
    return 'Choose a rating from 1 to 5 stars.';
  }
  return null;
}

String? reviewCommentError(String comment) {
  if (comment.trim().length > kReviewCommentMaxLength) {
    return 'Keep your comment under 1,000 characters.';
  }
  return null;
}
