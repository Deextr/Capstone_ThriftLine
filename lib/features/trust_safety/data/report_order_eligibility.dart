import '../../../models/enums.dart';
import '../../../models/order_model.dart';

/// Whether an order may appear in Report a Seller → Related order and be
/// linked on submit. Uses [OrderModel.status] (DB `order_status`), not
/// [OrderModel.paymentStatus] — payment may stay `paid` after cancellation.
///
/// Aligns with fulfillment-eligible statuses in delivery RPCs (`paid`,
/// `shipped`, `delivered`, `completed`, `disputed`).
bool isOrderEligibleForReportLink(OrderModel order) {
  switch (order.status) {
    case OrderStatus.cancelled:
    case OrderStatus.paymentPending:
    case OrderStatus.placed:
      return false;
    case OrderStatus.paymentConfirmed:
    case OrderStatus.preparing:
    case OrderStatus.shipped:
    case OrderStatus.outForDelivery:
    case OrderStatus.delivered:
    case OrderStatus.completed:
    case OrderStatus.disputed:
      return !order.isFailedCheckout;
  }
}
