import '../../../models/order_model.dart';

bool isCheckoutPaymentGroupPaid(Iterable<OrderModel> orders) {
  final list = orders.toList();
  if (list.isEmpty) return false;
  return list.every((order) => order.isPaidCheckout);
}

bool checkoutPaymentGroupNeedsPayment(Iterable<OrderModel> orders) {
  final list = orders.toList();
  if (list.isEmpty) return false;
  if (isCheckoutPaymentGroupPaid(list)) return false;
  if (list.any((order) => order.isFailedCheckout)) return false;
  return list.any((order) => order.needsBuyerPayment);
}

bool checkoutPaymentGroupHasFailure(Iterable<OrderModel> orders) {
  return orders.any((order) => order.isFailedCheckout);
}
