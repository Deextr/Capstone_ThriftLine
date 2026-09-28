import '../../../models/enums.dart';
import '../../../models/order_model.dart';
import '../../../models/shipment_model.dart';
import 'delivery_payment_hold.dart';

class AdminDeliveryDispute {
  const AdminDeliveryDispute({
    required this.id,
    required this.orderId,
    required this.shipmentId,
    required this.buyerId,
    this.sellerId,
    required this.reason,
    this.details,
    required this.status,
    this.adminNote,
    this.reviewedBy,
    required this.createdAt,
    this.resolvedAt,
    this.orderNumber,
    this.orderTitle,
    this.orderStatus,
    this.paymentStatus,
    this.buyerUsername = '',
    this.buyerDisplayName = '',
    this.sellerUsername = '',
    this.sellerDisplayName = '',
    this.sellerShopName,
    this.order,
    this.paymentHold,
  });

  final String id;
  final String orderId;
  final String shipmentId;
  final String buyerId;
  final String? sellerId;
  final DeliveryDisputeReason reason;
  final String? details;
  final String status;
  final String? adminNote;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? orderNumber;
  final String? orderTitle;
  final OrderStatus? orderStatus;
  final String? paymentStatus;
  final String buyerUsername;
  final String buyerDisplayName;
  final String sellerUsername;
  final String sellerDisplayName;
  final String? sellerShopName;
  final OrderModel? order;
  final DeliveryPaymentHold? paymentHold;

  ShipmentModel? get shipment => order?.shipment;

  factory AdminDeliveryDispute.fromSupabase(
    Map<String, dynamic> row, {
    OrderModel? order,
    Map<String, dynamic>? buyer,
    Map<String, dynamic>? seller,
    DeliveryPaymentHold? paymentHold,
  }) {
    DateTime? parseTime(Object? value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    final buyerUsername = buyer?['username'] as String? ?? '';
    final sellerUsername = seller?['username'] as String? ?? '';

    return AdminDeliveryDispute(
      id: row['dispute_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? order?.id ?? '',
      shipmentId: row['shipment_id'] as String? ?? '',
      buyerId: row['buyer_id'] as String? ?? '',
      sellerId: order?.sellerId ?? row['seller_id'] as String?,
      reason: DeliveryDisputeReason.fromDb(row['reason'] as String?),
      details: row['details'] as String?,
      status: row['status'] as String? ?? 'open',
      adminNote: row['admin_note'] as String?,
      reviewedBy: row['reviewed_by'] as String?,
      createdAt: parseTime(row['created_at']) ?? DateTime.now(),
      resolvedAt: parseTime(row['resolved_at']),
      orderNumber: order?.orderNumber ?? row['order_number'] as String?,
      orderTitle: order?.productTitle,
      orderStatus: order?.status,
      paymentStatus: order?.paymentStatus,
      buyerUsername: buyerUsername,
      buyerDisplayName:
          buyer?['full_name'] as String? ??
          (buyerUsername.isNotEmpty ? buyerUsername : 'Buyer'),
      sellerUsername: sellerUsername,
      sellerDisplayName:
          seller?['full_name'] as String? ??
          (sellerUsername.isNotEmpty ? sellerUsername : 'Seller'),
      sellerShopName: seller?['shop_name'] as String?,
      order: order,
      paymentHold: paymentHold,
    );
  }

  AdminDeliveryDispute copyWith({DeliveryPaymentHold? paymentHold}) {
    return AdminDeliveryDispute(
      id: id,
      orderId: orderId,
      shipmentId: shipmentId,
      buyerId: buyerId,
      sellerId: sellerId,
      reason: reason,
      details: details,
      status: status,
      adminNote: adminNote,
      reviewedBy: reviewedBy,
      createdAt: createdAt,
      resolvedAt: resolvedAt,
      orderNumber: orderNumber,
      orderTitle: orderTitle,
      orderStatus: orderStatus,
      paymentStatus: paymentStatus,
      buyerUsername: buyerUsername,
      buyerDisplayName: buyerDisplayName,
      sellerUsername: sellerUsername,
      sellerDisplayName: sellerDisplayName,
      sellerShopName: sellerShopName,
      order: order,
      paymentHold: paymentHold ?? this.paymentHold,
    );
  }
}
