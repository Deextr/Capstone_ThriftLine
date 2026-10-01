import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/data/buyer_to_rate_buckets.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/review_model.dart';

OrderModel _completedOrder(String id) {
  return OrderModel.fromSupabase({
    'order_id': id,
    'order_status': 'completed',
    'delivery_status': 'completed',
    'buyer_id': 'buyer-1',
    'seller_id': 'seller-1',
    'product_title': 'Vintage jacket',
    'total_amount': 500,
    'created_at': '2026-10-01T08:00:00Z',
  });
}

ReviewModel _buyerReview(String orderId) {
  return ReviewModel.fromSupabase({
    'review_id': 'r-$orderId',
    'order_id': orderId,
    'reviewer_id': 'buyer-1',
    'reviewed_user_id': 'seller-1',
    'rating': 5,
    'review_text': 'Great',
    'review_type': 'buyer_to_seller',
    'created_at': '2026-10-01T09:00:00Z',
  });
}

void main() {
  test('splits completed orders into pending and reviewed lists', () {
    final orders = [_completedOrder('o1'), _completedOrder('o2')];
    final reviews = {'o2': _buyerReview('o2')};

    final pending = ordersPendingBuyerReview(orders, reviews);
    expect(pending.map((order) => order.id), ['o1']);

    final history = buyerReviewHistory(orders, reviews);
    expect(history, hasLength(1));
    expect(history.first.order.id, 'o2');
    expect(history.first.review.id, 'r-o2');
  });
}
