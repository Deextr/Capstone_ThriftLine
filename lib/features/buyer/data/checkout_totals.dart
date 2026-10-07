/// Server and Flutter preview share these checkout numbers.
const double kCheckoutShippingPerSeller = 80;
const double kCheckoutPlatformFeeRate = 0.02;

int checkoutSellerCount(Iterable<String?> sellerIds) {
  return sellerIds
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .length;
}

/// Stable first seller for a one-payment checkout (matches SQL ORDER BY seller_id).
String? firstCheckoutSellerId(Iterable<String?> sellerIds) {
  final ids =
      sellerIds
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return ids.isEmpty ? null : ids.first;
}

double checkoutShippingFee(int sellerCount) {
  if (sellerCount <= 0) return 0;
  return sellerCount * kCheckoutShippingPerSeller;
}

double checkoutRoundCurrency(double value) {
  return double.parse(value.toStringAsFixed(2));
}

double checkoutPlatformFee(double subtotal) {
  if (subtotal <= 0) return 0;
  return checkoutRoundCurrency(subtotal * kCheckoutPlatformFeeRate);
}

double checkoutTotal({
  required double subtotal,
  required double shippingFee,
  required double platformFee,
}) {
  return checkoutRoundCurrency(subtotal + shippingFee + platformFee);
}
