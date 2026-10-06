import 'package:go_router/go_router.dart';

import '../../../models/order_model.dart';
import 'checkout_origin.dart';

/// Resolves buy-now vs cart for the payment screen (query params + order row).
CheckoutOrigin resolveCheckoutOrigin({
  required Uri uri,
  OrderModel? order,
}) {
  final fromUri = CheckoutOrigin.tryParse(
    uri.queryParameters[CheckoutOrigin.queryKey],
  );
  if (fromUri != null) return fromUri;
  if (order?.isBuyNowCheckout == true) return CheckoutOrigin.buyNow;
  return CheckoutOrigin.cart;
}

String? resolveCheckoutProductId({
  required Uri uri,
  OrderModel? order,
}) {
  final fromUri = uri.queryParameters[CheckoutOrigin.productQueryKey]?.trim();
  if (fromUri != null && fromUri.isNotEmpty) return fromUri;
  final fromOrder = order?.productId.trim();
  if (fromOrder != null && fromOrder.isNotEmpty) return fromOrder;
  return null;
}

Uri uriForPaymentContext(GoRouterState state) => state.uri;
