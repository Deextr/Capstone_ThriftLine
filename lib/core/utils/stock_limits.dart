import '../../models/enums.dart';

/// Highest quantity a buyer may purchase of a listing right now.
///
/// Auction listings are a single unique item (0 once sold). Fixed-price
/// listings use the seller's current [quantityAvailable].
int maxPurchasableQuantityFor({
  required SellingType sellingType,
  required int quantityAvailable,
}) {
  final stock = quantityAvailable < 0 ? 0 : quantityAvailable;
  if (stock <= 0) return 0;
  if (sellingType == SellingType.auction) return 1;
  return stock;
}

/// Caps a requested cart quantity to [maxPurchasable].
///
/// Returns `0` when nothing can be purchased (caller should drop the line).
int clampCartQuantity(int requested, int maxPurchasable) {
  if (maxPurchasable <= 0) return 0;
  if (requested < 1) return 1;
  return requested > maxPurchasable ? maxPurchasable : requested;
}

/// Buyer-facing copy when checkout quantity no longer matches live stock.
String? stockShortageMessage({
  required String title,
  required int requested,
  required int available,
}) {
  final name = title.trim().isEmpty ? 'This item' : title.trim();
  if (available <= 0) {
    return '$name is no longer available.';
  }
  if (requested > available) {
    return 'Available stock has changed. Only $available left of $name. '
        'Update the quantity and try again.';
  }
  return null;
}
