import '../../seller/data/listing_limit.dart';

/// Maps backend/PostgREST payment-start failures to buyer-safe copy.
String buyerFacingPaymentStartError(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return 'Unable to start payment right now. Please try again.';
  }
  if (listingLimitMessageFromError(Exception(text)) != null) {
    return 'We could not prepare your payment. Please try again in a moment.';
  }
  final lower = text.toLowerCase();
  if (lower.contains('is not unique') &&
      lower.contains('void_unpaid_checkout')) {
    return 'We could not prepare your payment. Please try again in a moment.';
  }
  if (lower.contains('listing_limit_reached')) {
    return 'We could not prepare your payment. Please try again in a moment.';
  }
  if (lower.contains('insufficient_stock')) {
    return 'Available stock has changed. Refresh your cart and try again.';
  }
  if (lower.contains('delivery address')) {
    return 'Add a delivery address before paying.';
  }
  if (lower.contains('choose card or gcash')) {
    return 'Choose Card or GCash.';
  }
  if (lower.contains('please sign in')) {
    return 'Please sign in to pay.';
  }
  if (lower.contains('order not found')) {
    return 'This checkout is no longer available. Return to your cart and try again.';
  }
  if (lower.contains('payment window') && lower.contains('auction')) {
    return 'Your payment window for this auction has ended.';
  }
  if (lower.contains('checkout was not completed')) {
    return text;
  }
  if (lower.contains('paymongo') ||
      lower.contains('checkout_session') ||
      lower.contains('postgrest') ||
      lower.contains('42725') ||
      lower.contains('check_violation')) {
    return 'Unable to start payment right now. Please try again.';
  }
  return text;
}
