import 'enums.dart';
import 'product_model.dart';

class UserBid {
  const UserBid({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.auctionId,
    this.isHighestBid = false,
    this.product,
  });

  final String id;
  final String productId;
  final String buyerId;
  final double amount;
  final BidStatus status;
  final DateTime createdAt;
  final String? auctionId;
  final bool isHighestBid;
  final ProductModel? product;

  factory UserBid.fromSupabase(Map<String, dynamic> row) {
    final auction = row['auction'] as Map<String, dynamic>? ?? {};
    final productMap = auction['product'] as Map<String, dynamic>?;

    ProductModel? productModel;
    if (productMap != null) {
      productModel = ProductModel.fromSupabase({
        ...productMap,
        'auctions': [auction],
      });
    }

    final buyerId = row['bidder_id'] as String? ?? '';
    final isHighest = row['is_highest_bid'] as bool? ?? false;
    final amount = (row['bid_amount'] as num?)?.toDouble() ?? 0.0;
    final auctionStatus = auction['status'] as String? ?? 'active';
    final rawEndsAt = auction['ends_at'] as String?;
    final endsAt = rawEndsAt != null ? DateTime.tryParse(rawEndsAt) : null;
    final isEnded = auctionStatus == 'ended' ||
        (endsAt != null && endsAt.isBefore(DateTime.now()));
    final winnerId = auction['winner_id'] as String?;

    BidStatus status;
    if (isEnded) {
      if (winnerId == buyerId || (winnerId == null && isHighest)) {
        status = BidStatus.won;
      } else {
        status = BidStatus.lost;
      }
    } else {
      if (isHighest) {
        status = BidStatus.winning;
      } else {
        status = BidStatus.outbid;
      }
    }

    return UserBid(
      id: row['bid_id'] as String? ?? '',
      productId: productModel?.id ?? auction['product_id'] as String? ?? '',
      buyerId: buyerId,
      amount: amount,
      status: status,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      auctionId: auction['auction_id'] as String?,
      isHighestBid: isHighest,
      product: productModel,
    );
  }

  UserBid copyWith({
    String? id,
    String? productId,
    String? buyerId,
    double? amount,
    BidStatus? status,
    DateTime? createdAt,
    String? auctionId,
    bool? isHighestBid,
    ProductModel? product,
  }) =>
      UserBid(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        buyerId: buyerId ?? this.buyerId,
        amount: amount ?? this.amount,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        auctionId: auctionId ?? this.auctionId,
        isHighestBid: isHighestBid ?? this.isHighestBid,
        product: product ?? this.product,
      );
}
