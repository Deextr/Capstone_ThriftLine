import '../../../models/enums.dart';
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

OrderModel _fallbackOrderForReview(ReviewModel review) {
  final shortOrderNum = review.orderId.length > 8
      ? review.orderId.substring(0, 8).toUpperCase()
      : review.orderId.toUpperCase();
  return OrderModel(
    id: review.orderId,
    orderNumber: shortOrderNum,
    productId: '',
    buyerId: review.reviewerId,
    sellerId: review.reviewedUserId,
    productTitle: 'Completed Order #$shortOrderNum',
    productImage: '',
    sellerName: 'Seller',
    buyerName: review.reviewerName,
    buyerAvatar: review.reviewerAvatar,
    amount: 0,
    shippingFee: 0,
    platformFee: 0,
    total: 0,
    status: OrderStatus.completed,
    paymentMethod: PaymentMethod.gcash,
    deliveryMethod: DeliveryMethod.standard,
    shippingAddress: '',
    createdAt: review.createdAt,
  );
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
        final order = byId[review.orderId] ?? _fallbackOrderForReview(review);
        return BuyerRatedPurchase(order: order, review: review);
      })
      .toList();
  entries.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));
  return entries;
}
