import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../buyer/data/buyer_purchase_category.dart';

/// Completed purchases where the buyer may leave a seller review.
List<OrderModel> completedOrdersEligibleForBuyerReview(
  Iterable<OrderModel> orders,
) {
  return orders
      .where((order) => order.isCompleted && orderIncludedInMyPurchases(order))
      .toList();
}

/// Completed orders with no buyer-to-seller review yet.
List<OrderModel> ordersPendingBuyerReview(
  Iterable<OrderModel> orders,
  Map<String, ReviewModel> myReviews,
) {
  return completedOrdersEligibleForBuyerReview(
      orders,
    ).where((order) => myReviews[order.id] == null).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class BuyerRatedPurchase {
  const BuyerRatedPurchase({required this.order, required this.review});

  final OrderModel order;
  final ReviewModel review;
}

/// Submitted buyer-to-seller reviews paired with their orders.
List<BuyerRatedPurchase> buyerReviewHistory(
  Iterable<OrderModel> orders,
  Map<String, ReviewModel> myReviews,
) {
  final byId = {for (final order in orders) order.id: order};
  final entries = myReviews.values
      .where((review) => review.reviewType == 'buyer_to_seller')
      .map((review) {
        final order = byId[review.orderId];
        if (order == null) return null;
        return BuyerRatedPurchase(order: order, review: review);
      })
      .whereType<BuyerRatedPurchase>()
      .toList();
  entries.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));
  return entries;
}
