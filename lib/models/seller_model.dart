import 'base_model.dart';

class SellerModel extends BaseModel {
  const SellerModel({
    required this.id,
    required this.userId,
    required this.shopName,
    this.shopDescription,
    this.rating = 0,
    this.totalSales = 0,
    this.isVerified = false,
    this.productIds = const [],
  });

  final String id;
  final String userId;
  final String shopName;
  final String? shopDescription;
  final double rating;
  final int totalSales;
  final bool isVerified;
  final List<String> productIds;

  factory SellerModel.fromJson(Map<String, dynamic> json) => SellerModel(
        id: json['id'] as String,
        userId: json['userId'] as String,
        shopName: json['shopName'] as String,
        shopDescription: json['shopDescription'] as String?,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        totalSales: json['totalSales'] as int? ?? 0,
        isVerified: json['isVerified'] as bool? ?? false,
        productIds: (json['productIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'shopName': shopName,
        'shopDescription': shopDescription,
        'rating': rating,
        'totalSales': totalSales,
        'isVerified': isVerified,
        'productIds': productIds,
      };

  SellerModel copyWith({
    String? id,
    String? userId,
    String? shopName,
    String? shopDescription,
    double? rating,
    int? totalSales,
    bool? isVerified,
    List<String>? productIds,
  }) =>
      SellerModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        shopName: shopName ?? this.shopName,
        shopDescription: shopDescription ?? this.shopDescription,
        rating: rating ?? this.rating,
        totalSales: totalSales ?? this.totalSales,
        isVerified: isVerified ?? this.isVerified,
        productIds: productIds ?? this.productIds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SellerModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
