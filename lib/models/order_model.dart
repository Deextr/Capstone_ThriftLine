import 'enums.dart';

class OrderLineItem {
  const OrderLineItem({
    required this.id,
    this.productId,
    required this.title,
    this.imageUrl,
    this.size,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final String id;
  final String? productId;
  final String title;
  final String? imageUrl;
  final String? size;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  factory OrderLineItem.fromSupabase(Map<String, dynamic> row) {
    return OrderLineItem(
      id: row['order_item_id'] as String? ?? row['id'] as String? ?? '',
      productId: row['product_id'] as String?,
      title: row['title'] as String? ?? 'Item',
      imageUrl: row['image_url'] as String?,
      size: row['size'] as String?,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0,
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      lineTotal: (row['line_total'] as num?)?.toDouble() ?? 0,
    );
  }
}

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
    this.auctionId,
    this.source = 'cart',
    this.paymentStatus = 'pending',
    this.items = const [],
    this.addressMissing = false,
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
  final String? auctionId;
  final String source;
  final String paymentStatus;
  final List<OrderLineItem> items;
  final bool addressMissing;

  bool get isPaymentPending =>
      status == OrderStatus.paymentPending || status == OrderStatus.placed;

  factory OrderModel.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? buyer,
    Map<String, dynamic>? seller,
  }) {
    final rawItems = row['items'] ?? row['order_items'];
    final items = <OrderLineItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          items.add(OrderLineItem.fromSupabase(raw));
        } else if (raw is Map) {
          items.add(OrderLineItem.fromSupabase(Map<String, dynamic>.from(raw)));
        }
      }
    }
    final first = items.isNotEmpty ? items.first : null;
    final address = row['shipping_address'];
    var formatted = '';
    var addressMissing = true;
    if (address is Map) {
      formatted = address['formatted'] as String? ?? '';
      addressMissing =
          formatted.trim().isEmpty &&
          (address['street_address'] as String? ?? '').trim().isEmpty;
      if (formatted.trim().isEmpty) {
        formatted =
            [address['street_address'], address['barangay'], address['city']]
                .whereType<String>()
                .where((part) => part.trim().isNotEmpty)
                .join(', ');
      }
    } else if (address is String) {
      formatted = address;
      addressMissing = formatted.trim().isEmpty;
    }

    final sellerName =
        seller?['shop_name'] as String? ??
        seller?['full_name'] as String? ??
        seller?['username'] as String? ??
        'Seller';
    final buyerName =
        buyer?['full_name'] as String? ??
        buyer?['username'] as String? ??
        'Buyer';

    return OrderModel(
      id: row['order_id'] as String? ?? '',
      orderNumber: row['order_number'] as String? ?? '',
      productId: first?.productId ?? '',
      buyerId: row['buyer_id'] as String? ?? '',
      sellerId: row['seller_id'] as String? ?? '',
      productTitle: first?.title ?? 'Order',
      productImage: first?.imageUrl ?? '',
      sellerName: sellerName,
      buyerName: buyerName,
      buyerAvatar: buyer?['avatar'] as String? ?? '',
      amount: (row['subtotal'] as num?)?.toDouble() ?? 0,
      shippingFee: (row['shipping_fee'] as num?)?.toDouble() ?? 0,
      platformFee: (row['platform_fee'] as num?)?.toDouble() ?? 0,
      total:
          (row['total_amount'] as num?)?.toDouble() ??
          (row['total'] as num?)?.toDouble() ??
          0,
      status: orderStatusFromDb(
        row['order_status'] as String? ?? row['status'] as String?,
      ),
      paymentMethod: PaymentMethod.unpaid,
      deliveryMethod: DeliveryMethod.standard,
      shippingAddress: formatted,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      trackingNumber: row['tracking_number'] as String?,
      courier: row['courier'] as String?,
      quantity: first?.quantity ?? 1,
      size: first?.size,
      auctionId: row['auction_id'] as String?,
      source:
          row['order_type'] as String? ?? row['source'] as String? ?? 'cart',
      paymentStatus:
          row['payment_status'] as String? ??
          ((row['order_status'] as String? ?? row['status'] as String?) ==
                  'pending'
              ? 'pending'
              : 'unpaid'),
      items: items,
      addressMissing: addressMissing,
    );
  }

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
    String? auctionId,
    String? source,
    String? paymentStatus,
    List<OrderLineItem>? items,
    bool? addressMissing,
  }) => OrderModel(
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
    auctionId: auctionId ?? this.auctionId,
    source: source ?? this.source,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    items: items ?? this.items,
    addressMissing: addressMissing ?? this.addressMissing,
  );
}
