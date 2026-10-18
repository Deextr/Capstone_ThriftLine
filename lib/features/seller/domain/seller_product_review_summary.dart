import '../../../models/review_model.dart';

/// Product context for a buyer review on one of the seller's orders.
class SellerOrderProductRef {
  const SellerOrderProductRef({
    required this.productId,
    required this.productTitle,
    required this.productImageUrl,
  });

  final String productId;
  final String productTitle;
  final String productImageUrl;
}

/// Aggregated buyer reviews for one product the seller has sold.
class SellerProductReviewSummary {
  const SellerProductReviewSummary({
    required this.productId,
    required this.productTitle,
    required this.productImageUrl,
    required this.reviews,
  });

  final String productId;
  final String productTitle;
  final String productImageUrl;
  final List<ReviewModel> reviews;

  int get reviewCount => reviews.length;

  double get averageRating {
    if (reviews.isEmpty) return 0;
    final sum = reviews.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / reviews.length;
  }
}

List<SellerProductReviewSummary> groupReviewsByProduct({
  required List<ReviewModel> reviews,
  required Map<String, SellerOrderProductRef> orderProducts,
}) {
  final byProduct = <String, List<ReviewModel>>{};
  final meta = <String, SellerOrderProductRef>{};

  for (final review in reviews) {
    final ref = orderProducts[review.orderId];
    if (ref == null || ref.productId.isEmpty) continue;
    meta[ref.productId] = ref;
    byProduct.putIfAbsent(ref.productId, () => []).add(review);
  }

  final summaries = byProduct.entries.map((entry) {
    final ref = meta[entry.key]!;
    final sorted = List<ReviewModel>.from(entry.value)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SellerProductReviewSummary(
      productId: ref.productId,
      productTitle: ref.productTitle,
      productImageUrl: ref.productImageUrl,
      reviews: sorted,
    );
  }).toList();

  summaries.sort((a, b) {
    final byDate = b.reviews.first.createdAt.compareTo(
      a.reviews.first.createdAt,
    );
    if (byDate != 0) return byDate;
    return b.reviewCount.compareTo(a.reviewCount);
  });

  return summaries;
}
