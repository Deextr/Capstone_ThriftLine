import 'enums.dart';
import 'return_shipment.dart';
import 'shipment_model.dart';

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
    this.addressId,
<<<<<<< HEAD
=======
    this.addressName,
>>>>>>> checkout-address-label-fix
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
    this.shipment,
    this.itemReturn,
    this.paymentDueAt,
    this.checkoutGroupId,
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
  final String? addressId;
<<<<<<< HEAD
=======
  final String? addressName;
>>>>>>> checkout-address-label-fix
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
  final ShipmentModel? shipment;
  final ReturnShipment? itemReturn;
  final DateTime? paymentDueAt;
  final String? checkoutGroupId;

  bool get isAuctionObligation =>
      (auctionId != null && auctionId!.isNotEmpty) || source == 'auction';

  bool get isPaymentWindowOpen {
    final due = paymentDueAt;
    if (due == null) return needsBuyerPayment;
    return needsBuyerPayment && due.isAfter(DateTime.now());
  }

  bool get isRefundedSale => paymentStatus == 'refunded';

  bool get isPaymentPending =>
      status == OrderStatus.paymentPending || status == OrderStatus.placed;

  bool get isPaymentUnsuccessful =>
      paymentStatus == 'failed' || paymentStatus == 'expired';

  /// Failed unpaid checkout — not a completed purchase or seller sale.
  bool get isFailedCheckout =>
      !isRefundedSale &&
      (isPaymentUnsuccessful ||
          (status == OrderStatus.cancelled &&
              (auctionId == null || auctionId!.isEmpty)));

  bool get isExpiredCheckout => paymentStatus == 'expired';

  /// Unpaid checkout the buyer can still finish. Not a completed purchase.
  bool get needsBuyerPayment => isPaymentPending && !isFailedCheckout;

  /// Auction wins require payment. Abandoned fixed-price checkouts do not.
  bool get showsAsAwaitingPayment => needsBuyerPayment && isAuctionObligation;

  bool get showsInPurchaseHistory => !isPaymentPending && !isFailedCheckout;

  bool get isToShip {
    if (isFailedCheckout || isPaymentPending) return false;
    if (status == OrderStatus.cancelled ||
        status == OrderStatus.completed ||
        status == OrderStatus.disputed) {
      return false;
    }
    final delivery = shipment?.deliveryStatus;
    if (delivery == null) {
      return status == OrderStatus.paymentConfirmed ||
          status == OrderStatus.preparing;
    }
    return delivery.isPreparing;
  }

  bool get isInTransit => shipment?.deliveryStatus.isInTransit ?? false;

  bool get isInspecting =>
      shipment?.isInspecting == true || status == OrderStatus.delivered;

  bool get isDeliveryFailed => shipment?.isFailed == true;

  bool get isDisputed =>
      status == OrderStatus.disputed || shipment?.isDisputed == true;

  bool get isCompleted =>
      status == OrderStatus.completed || shipment?.isCompleted == true;

  bool get isShippedTab =>
      isInTransit || isInspecting || isDeliveryFailed || isDisputed;

  bool get canArrangeDelivery =>
      !isFailedCheckout &&
      !isPaymentPending &&
      !isCompleted &&
      !isDisputed &&
      (shipment == null || shipment!.canEditRider);

  bool get isSellerVisible => !isPaymentPending && !isFailedCheckout;

  /// Paid orders still in fulfillment. Unpaid checkouts stay on To Pay;
  /// completed purchases stay in Purchase History.
  bool get isTrackable =>
      itemReturn?.isOpen == true ||
      (showsInPurchaseHistory &&
          !isCompleted &&
          status != OrderStatus.cancelled &&
          (isToShip ||
              isInTransit ||
              isInspecting ||
              isDeliveryFailed ||
              isDisputed));

  String get trackingStatusLabel =>
      shipment?.deliveryStatus.label ?? orderStatusLabel(status);

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
      paymentMethod:
          orderStatusFromDb(
                row['order_status'] as String? ?? row['status'] as String?,
              ) ==
              OrderStatus.paymentPending
          ? PaymentMethod.unpaid
          : PaymentMethod.paymongo,
      deliveryMethod: DeliveryMethod.standard,
      shippingAddress: formatted,
      addressId: address is Map ? address['address_id'] as String? : null,
<<<<<<< HEAD
=======
      addressName: address is Map
          ? address['recipient_name'] as String?
          : null,
>>>>>>> checkout-address-label-fix
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
      paymentStatus: paymentStatusFromOrderRow(row),
      items: items,
      addressMissing: addressMissing,
      shipment: shipmentFromOrderRow(row),
      itemReturn: returnShipmentFromOrderRow(row),
      paymentDueAt: row['payment_due_at'] != null
          ? DateTime.tryParse(row['payment_due_at'] as String)
          : null,
      checkoutGroupId: row['checkout_group_id'] as String?,
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
    String? addressId,
<<<<<<< HEAD
=======
    String? addressName,
>>>>>>> checkout-address-label-fix
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
    ShipmentModel? shipment,
    ReturnShipment? itemReturn,
    DateTime? paymentDueAt,
    String? checkoutGroupId,
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
    addressId: addressId ?? this.addressId,
<<<<<<< HEAD
=======
    addressName: addressName ?? this.addressName,
>>>>>>> checkout-address-label-fix
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
    shipment: shipment ?? this.shipment,
    itemReturn: itemReturn ?? this.itemReturn,
    paymentDueAt: paymentDueAt ?? this.paymentDueAt,
    checkoutGroupId: checkoutGroupId ?? this.checkoutGroupId,
  );
}

String paymentStatusFromOrderRow(Map<String, dynamic> row) {
  final statuses = <String>[];
  final nested = row['payments'];
  if (nested is List) {
    for (final raw in nested) {
      if (raw is Map) {
        final status = raw['payment_status']?.toString().trim();
        if (status != null && status.isNotEmpty) statuses.add(status);
      }
    }
  } else if (nested is Map) {
    final status = nested['payment_status']?.toString().trim();
    if (status != null && status.isNotEmpty) statuses.add(status);
  }
  final top = row['payment_status']?.toString().trim();
  if (top != null && top.isNotEmpty) statuses.add(top);
  if (statuses.contains('refunded')) return 'refunded';
  if (statuses.contains('paid')) return 'paid';
  if (statuses.contains('expired')) return 'expired';
  if (statuses.contains('failed')) return 'failed';
  if (statuses.contains('pending')) return 'pending';
  final orderStatus =
      row['order_status'] as String? ?? row['status'] as String?;
  return orderStatus == 'pending' ? 'pending' : 'unpaid';
}
