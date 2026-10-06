/// How the buyer reached checkout / payment (fixed-price flows).
enum CheckoutOrigin {
  buyNow,
  cart;

  static const queryKey = 'source';
  static const productQueryKey = 'product';

  static CheckoutOrigin? tryParse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'buy_now':
      case 'buynow':
        return CheckoutOrigin.buyNow;
      case 'cart':
        return CheckoutOrigin.cart;
      default:
        return null;
    }
  }

  String get routeValue => switch (this) {
    CheckoutOrigin.buyNow => 'buy_now',
    CheckoutOrigin.cart => 'cart',
  };

  static CheckoutOrigin fromOrderCheckoutSource(String? raw) {
    return tryParse(raw) ?? CheckoutOrigin.cart;
  }

  bool get restoreCartOnAbandon => this == CheckoutOrigin.cart;
}
