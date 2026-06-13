import 'base_model.dart';

class BuyerModel extends BaseModel {
  const BuyerModel({
    required this.id,
    required this.userId,
    this.savedProductIds = const [],
    this.totalPurchases = 0,
    this.rating,
  });

  final String id;
  final String userId;
  final List<String> savedProductIds;
  final int totalPurchases;
  final double? rating;

  factory BuyerModel.fromJson(Map<String, dynamic> json) => BuyerModel(
        id: json['id'] as String,
        userId: json['userId'] as String,
        savedProductIds: (json['savedProductIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        totalPurchases: json['totalPurchases'] as int? ?? 0,
        rating: (json['rating'] as num?)?.toDouble(),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'savedProductIds': savedProductIds,
        'totalPurchases': totalPurchases,
        'rating': rating,
      };

  BuyerModel copyWith({
    String? id,
    String? userId,
    List<String>? savedProductIds,
    int? totalPurchases,
    double? rating,
  }) =>
      BuyerModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        savedProductIds: savedProductIds ?? this.savedProductIds,
        totalPurchases: totalPurchases ?? this.totalPurchases,
        rating: rating ?? this.rating,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuyerModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
