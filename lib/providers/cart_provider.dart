import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/product_model.dart';

/// Represents a single item in the cart.
class CartItem {
  const CartItem({
    required this.product,
    this.quantity = 1,
  });

  final ProductModel product;
  final int quantity;

  double get subtotal => product.price * quantity;

  /// Whether this item can be purchased directly (fixed price or "both" with buyNow).
  bool get isFixedPrice =>
      product.sellingType == SellingType.fixedPrice ||
      (product.sellingType == SellingType.both && product.buyNowEnabled);

  /// Whether this item is auction-only.
  bool get isAuction =>
      product.sellingType == SellingType.auction ||
      (product.sellingType == SellingType.both && !product.buyNowEnabled);

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, quantity: quantity ?? this.quantity);
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  /// Fixed-price items that can be checked out directly.
  List<CartItem> get fixedPriceItems =>
      _items.where((i) => i.isFixedPrice).toList();

  /// Auction items shown for reference / bidding status.
  List<CartItem> get auctionItems =>
      _items.where((i) => i.isAuction).toList();

  int get itemCount => _items.length;
  int get fixedPriceCount => fixedPriceItems.length;
  int get auctionCount => auctionItems.length;

  bool isInCart(String productId) =>
      _items.any((i) => i.product.id == productId);

  double get subtotal =>
      fixedPriceItems.fold(0.0, (sum, item) => sum + item.subtotal);

  double get shippingFee => fixedPriceItems.isEmpty ? 0 : 80.0;

  double get platformFee => subtotal * 0.02;

  double get total => subtotal + shippingFee + platformFee;

  void addToCart(ProductModel product) {
    final index = _items.indexWhere((i) => i.product.id == product.id);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(
        quantity: _items[index].quantity + 1,
      );
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  void clearFixedPriceItems() {
    _items.removeWhere((i) => i.isFixedPrice);
    notifyListeners();
  }
}
