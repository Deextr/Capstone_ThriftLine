import 'enums.dart';
import 'product_model.dart';

/// Domain model for a user's cart item, mapped from Supabase `cart_items` table.
class CartItemModel {
  const CartItemModel({
    required this.id,
    required this.userId,
    required this.productId,
    this.quantity = 1,
    this.product,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String productId;
  final int quantity;
  final ProductModel? product;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get price => product?.displayPrice ?? product?.price ?? 0.0;

  double get subtotal => price * quantity;

  /// Whether this item can be purchased directly (fixed price or "both" with buyNow).
  bool get isFixedPrice =>
      product != null &&
      (product!.sellingType == SellingType.fixedPrice ||
          (product!.sellingType == SellingType.both && product!.buyNowEnabled));

  /// Whether this item is auction-only.
  bool get isAuction =>
      product != null &&
      (product!.sellingType == SellingType.auction ||
          (product!.sellingType == SellingType.both && !product!.buyNowEnabled));

  CartItemModel copyWith({
    String? id,
    String? userId,
    String? productId,
    int? quantity,
    ProductModel? product,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      product: product ?? this.product,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CartItemModel.fromJson(
    Map<String, dynamic> json, {
    Map<String, Map<String, dynamic>>? sellerProfilesMap,
  }) {
    final productRaw = json['product'] ?? json['products'];
    ProductModel? product;
    if (productRaw is Map<String, dynamic>) {
      final sellerId = productRaw['seller_id'] as String?;
      product = ProductModel.fromSupabase(
        productRaw,
        sellerProfile:
            sellerId != null && sellerProfilesMap != null ? sellerProfilesMap[sellerId] : null,
      );
    }

    return CartItemModel(
      id: json['cart_item_id'] as String? ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      product: product,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'cart_item_id': id,
        'user_id': userId,
        'product_id': productId,
        'quantity': quantity,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}
