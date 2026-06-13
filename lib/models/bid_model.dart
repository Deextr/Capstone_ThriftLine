import 'enums.dart';

class UserBid {
  const UserBid({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String buyerId;
  final double amount;
  final BidStatus status;
  final DateTime createdAt;

  UserBid copyWith({
    String? id,
    String? productId,
    String? buyerId,
    double? amount,
    BidStatus? status,
    DateTime? createdAt,
  }) =>
      UserBid(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        buyerId: buyerId ?? this.buyerId,
        amount: amount ?? this.amount,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
