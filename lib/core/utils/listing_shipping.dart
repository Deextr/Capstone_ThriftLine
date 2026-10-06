import '../../models/product_model.dart';

/// Mirrors `listing_shipping_mode` and server-side shipping calculators.
enum ListingShippingMode {
  free('free'),
  fixedFee('fixed_fee'),
  quantityThreshold('quantity_threshold'),
  bidThreshold('bid_threshold');

  const ListingShippingMode(this.dbValue);
  final String dbValue;

  static ListingShippingMode fromDb(String? value) {
    for (final mode in ListingShippingMode.values) {
      if (mode.dbValue == value) return mode;
    }
    return ListingShippingMode.fixedFee;
  }
}

class CartShippingLine {
  const CartShippingLine({
    required this.productId,
    required this.quantity,
    required this.mode,
    required this.shippingFee,
    this.freeShippingQtyThreshold,
  });

  final String productId;
  final int quantity;
  final ListingShippingMode mode;
  final double shippingFee;
  final int? freeShippingQtyThreshold;
}

/// Preview only — checkout uses [calculate_shop_fixed_shipping] on the server.
double calculateShopFixedShippingPreview(List<CartShippingLine> lines) {
  if (lines.isEmpty) return 0;

  var totalQty = 0;
  var allFree = true;
  var hasPaid = false;
  var maxFee = 0.0;
  int? minThreshold;

  for (final line in lines) {
    if (line.quantity <= 0) continue;
    totalQty += line.quantity;

    if (line.mode == ListingShippingMode.free) continue;

    allFree = false;
    hasPaid = true;

    if (line.mode == ListingShippingMode.fixedFee ||
        line.mode == ListingShippingMode.quantityThreshold) {
      maxFee = maxFee < line.shippingFee ? line.shippingFee : maxFee;
    }

    if (line.mode == ListingShippingMode.quantityThreshold &&
        line.freeShippingQtyThreshold != null) {
      final t = line.freeShippingQtyThreshold!;
      minThreshold = minThreshold == null
          ? t
          : (t < minThreshold ? t : minThreshold);
    }
  }

  if (totalQty <= 0) return 0;
  if (allFree) return 0;
  if (minThreshold != null && totalQty >= minThreshold) return 0;
  if (hasPaid) return maxFee;
  return 80;
}

double previewAuctionShipping({
  required ListingShippingMode mode,
  required double winningBid,
  required double shippingFee,
  double? freeShippingBidThreshold,
}) {
  switch (mode) {
    case ListingShippingMode.free:
      return 0;
    case ListingShippingMode.bidThreshold:
      if (freeShippingBidThreshold != null &&
          winningBid >= freeShippingBidThreshold) {
        return 0;
      }
      return shippingFee < 0 ? 0 : shippingFee;
    case ListingShippingMode.fixedFee:
      return shippingFee < 0 ? 0 : shippingFee;
    case ListingShippingMode.quantityThreshold:
      return shippingFee < 0 ? 0 : shippingFee;
  }
}

List<CartShippingLine> cartShippingLinesFromProducts(
  Iterable<({ProductModel product, int quantity})> items,
) {
  return [
    for (final row in items)
      CartShippingLine(
        productId: row.product.id,
        quantity: row.quantity,
        mode: row.product.shippingMode,
        shippingFee: row.product.shippingFee,
        freeShippingQtyThreshold: row.product.freeShippingQtyThreshold,
      ),
  ];
}

String fixedPriceShippingBuyerLabel(ProductModel product) {
  switch (product.shippingMode) {
    case ListingShippingMode.free:
      return 'Free shipping';
    case ListingShippingMode.fixedFee:
      return 'Shipping fee applies at checkout';
    case ListingShippingMode.quantityThreshold:
      final threshold = product.freeShippingQtyThreshold;
      if (threshold != null) {
        return 'Free shipping when you buy $threshold items from this shop';
      }
      return 'Shipping fee applies at checkout';
    case ListingShippingMode.bidThreshold:
      return 'Shipping fee applies at checkout';
  }
}

String auctionShippingBuyerLabel(ProductModel product) {
  switch (product.shippingMode) {
    case ListingShippingMode.free:
      return 'Free shipping';
    case ListingShippingMode.fixedFee:
      return 'Shipping applies to the winning bid';
    case ListingShippingMode.bidThreshold:
      final at = product.freeShippingBidThreshold;
      if (at != null) {
        return 'Free shipping when winning bid reaches ${_formatMoney(at)}';
      }
      return 'Shipping applies to the winning bid';
    case ListingShippingMode.quantityThreshold:
      return 'Shipping applies to the winning bid';
  }
}

String _formatMoney(double value) {
  if (value == value.roundToDouble()) {
    return '₱${value.toStringAsFixed(0)}';
  }
  return '₱${value.toStringAsFixed(2)}';
}
