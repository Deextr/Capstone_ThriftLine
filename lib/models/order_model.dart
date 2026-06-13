import 'enums.dart';

class OrderModel {
  const OrderModel({
    required this.id,
    required this.orderNumber,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.productTitle,
    required this.productImage,
    required this.sellerName,
    required this.buyerName,
    required this.buyerAvatar,
    required this.amount,
    required this.shippingFee,
    required this.platformFee,
    required this.total,
    required this.status,
    required this.paymentMethod,
    required this.deliveryMethod,
    required this.shippingAddress,
    required this.createdAt,
    this.trackingNumber,
    this.courier,
    this.estimatedDelivery,
    this.paymentProofSubmitted = false,
    this.quantity = 1,
    this.size,
  });

  final String id;
  final String orderNumber;
  final String productId;
  final String buyerId;
  final String sellerId;
  final String productTitle;
  final String productImage;
  final String sellerName;
  final String buyerName;
  final String buyerAvatar;
  final double amount;
  final double shippingFee;
  final double platformFee;
  final double total;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final DeliveryMethod deliveryMethod;
  final String shippingAddress;
  final DateTime createdAt;
  final String? trackingNumber;
  final String? courier;
  final DateTime? estimatedDelivery;
  final bool paymentProofSubmitted;
  final int quantity;
  final String? size;

  OrderModel copyWith({
    String? id,
    String? orderNumber,
    String? productId,
    String? buyerId,
    String? sellerId,
    String? productTitle,
    String? productImage,
    String? sellerName,
    String? buyerName,
    String? buyerAvatar,
    double? amount,
    double? shippingFee,
    double? platformFee,
    double? total,
    OrderStatus? status,
    PaymentMethod? paymentMethod,
    DeliveryMethod? deliveryMethod,
    String? shippingAddress,
    DateTime? createdAt,
    String? trackingNumber,
    String? courier,
    DateTime? estimatedDelivery,
    bool? paymentProofSubmitted,
    int? quantity,
    String? size,
  }) =>
      OrderModel(
        id: id ?? this.id,
        orderNumber: orderNumber ?? this.orderNumber,
        productId: productId ?? this.productId,
        buyerId: buyerId ?? this.buyerId,
        sellerId: sellerId ?? this.sellerId,
        productTitle: productTitle ?? this.productTitle,
        productImage: productImage ?? this.productImage,
        sellerName: sellerName ?? this.sellerName,
        buyerName: buyerName ?? this.buyerName,
        buyerAvatar: buyerAvatar ?? this.buyerAvatar,
        amount: amount ?? this.amount,
        shippingFee: shippingFee ?? this.shippingFee,
        platformFee: platformFee ?? this.platformFee,
        total: total ?? this.total,
        status: status ?? this.status,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        deliveryMethod: deliveryMethod ?? this.deliveryMethod,
        shippingAddress: shippingAddress ?? this.shippingAddress,
        createdAt: createdAt ?? this.createdAt,
        trackingNumber: trackingNumber ?? this.trackingNumber,
        courier: courier ?? this.courier,
        estimatedDelivery: estimatedDelivery ?? this.estimatedDelivery,
        paymentProofSubmitted: paymentProofSubmitted ?? this.paymentProofSubmitted,
        quantity: quantity ?? this.quantity,
        size: size ?? this.size,
      );
}
