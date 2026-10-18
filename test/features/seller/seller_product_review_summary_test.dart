import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/seller_product_review_summary.dart';
import 'package:thriftline/models/review_model.dart';

ReviewModel _review({
  required String id,
  required String orderId,
  required int rating,
}) {
  return ReviewModel(
    id: id,
    orderId: orderId,
    reviewerId: 'buyer-1',
    reviewerName: 'Buyer',
    reviewerUsername: 'buyer',
    reviewerAvatar: '',
    reviewedUserId: 'seller-1',
    rating: rating,
    comment: 'Nice',
    reviewType: 'buyer_to_seller',
    createdAt: DateTime(2026, 1, id.hashCode % 28 + 1),
  );
}

void main() {
  test('groupReviewsByProduct groups by product and averages ratings', () {
    final summaries = groupReviewsByProduct(
      reviews: [
        _review(id: 'r1', orderId: 'o1', rating: 5),
        _review(id: 'r2', orderId: 'o2', rating: 3),
        _review(id: 'r3', orderId: 'o3', rating: 4),
      ],
      orderProducts: {
        'o1': const SellerOrderProductRef(
          productId: 'p1',
          productTitle: 'Jacket',
          productImageUrl: '',
        ),
        'o2': const SellerOrderProductRef(
          productId: 'p1',
          productTitle: 'Jacket',
          productImageUrl: '',
        ),
        'o3': const SellerOrderProductRef(
          productId: 'p2',
          productTitle: 'Shoes',
          productImageUrl: '',
        ),
      },
    );

    expect(summaries.length, 2);
    final jacket = summaries.firstWhere((s) => s.productId == 'p1');
    expect(jacket.reviewCount, 2);
    expect(jacket.averageRating, 4);
  });
}
