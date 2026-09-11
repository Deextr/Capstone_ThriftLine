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
    this.auctionCurrentPrice,
    this.auctionIncrement,
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
  final double? auctionCurrentPrice;
  final double? auctionIncrement;
  final ProductModel? product;

  factory UserBid.fromSupabase(
    Map<String, dynamic> row, {
    ProductModel? product,
  }) {
    final nestedAuction = row['auction'];
    final auction = nestedAuction is Map<String, dynamic>
        ? nestedAuction
        : <String, dynamic>{
            'auction_id': row['auction_id'],
            'product_id': row['product_id'],
            'starting_price': row['starting_price'],
            'minimum_increment': row['minimum_increment'],
            'current_price': row['current_price'],
            'winner_id': row['winner_id'],
            'starts_at': row['starts_at'],
            'ends_at': row['ends_at'],
            'status': row['auction_status'] ?? row['status'],
            if (row['product'] != null) 'product': row['product'],
          };

    final productMap = auction['product'] as Map<String, dynamic>?;
    ProductModel? productModel = product;
    if (productModel == null && productMap != null) {
      productModel = ProductModel.fromSupabase({
        ...productMap,
        'auctions': [auction],
      });
    }

    final buyerId = row['bidder_id'] as String? ?? '';
    final isHighest = row['is_highest_bid'] as bool? ?? false;
    final amount = (row['bid_amount'] as num?)?.toDouble() ?? 0.0;
    final auctionStatus =
        (auction['status'] as String?) ??
        (row['auction_status'] as String?) ??
        'active';
    final winnerId =
        auction['winner_id'] as String? ?? row['winner_id'] as String?;

    BidStatus status;
    final statusRaw = row['bid_status'] as String?;
    if (statusRaw != null && statusRaw.isNotEmpty) {
      status = bidStatusFromView(statusRaw);
    } else {
      final isEnded = auctionStatus == 'ended' || auctionStatus == 'cancelled';
      if (isEnded) {
        if (winnerId == buyerId || (winnerId == null && isHighest)) {
          status = BidStatus.won;
        } else {
          status = BidStatus.lost;
        }
      } else if (isHighest) {
        status = BidStatus.winning;
      } else {
        status = BidStatus.outbid;
      }
    }

    return UserBid(
      id: row['bid_id'] as String? ?? '',
      productId:
          productModel?.id ??
          auction['product_id'] as String? ??
          row['product_id'] as String? ??
          '',
      buyerId: buyerId,
      amount: amount,
      status: status,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      auctionId:
          auction['auction_id'] as String? ?? row['auction_id'] as String?,
      isHighestBid: isHighest,
      auctionCurrentPrice:
          (auction['current_price'] as num?)?.toDouble() ??
          (row['current_price'] as num?)?.toDouble(),
      auctionIncrement:
          (auction['minimum_increment'] as num?)?.toDouble() ??
          (row['minimum_increment'] as num?)?.toDouble(),
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
    double? auctionCurrentPrice,
    double? auctionIncrement,
    ProductModel? product,
  }) => UserBid(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    buyerId: buyerId ?? this.buyerId,
    amount: amount ?? this.amount,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    auctionId: auctionId ?? this.auctionId,
    isHighestBid: isHighestBid ?? this.isHighestBid,
    auctionCurrentPrice: auctionCurrentPrice ?? this.auctionCurrentPrice,
    auctionIncrement: auctionIncrement ?? this.auctionIncrement,
    product: product ?? this.product,
  );
}

class AuctionBidQuote {
  const AuctionBidQuote({
    required this.currentPrice,
    required this.minimumIncrement,
    required this.status,
    this.endsAt,
  });

  final double currentPrice;
  final double minimumIncrement;
  final String status;
  final DateTime? endsAt;

  double get minimumNextBid => currentPrice + minimumIncrement;

  bool get isAcceptingBids {
    if (status != 'active') return false;
    if (endsAt == null) return true;
    return endsAt!.isAfter(DateTime.now());
  }
}

BidStatus bidStatusFromView(String value) {
  switch (value) {
    case 'winning':
    case 'leading':
      return BidStatus.winning;
    case 'outbid':
      return BidStatus.outbid;
    case 'won':
      return BidStatus.won;
    case 'lost':
      return BidStatus.lost;
    default:
      return BidStatus.fromString(value);
  }
}
