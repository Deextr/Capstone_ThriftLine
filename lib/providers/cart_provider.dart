import 'package:flutter/foundation.dart';

import '../core/services/supabase_service.dart';
import '../models/enums.dart';
import '../models/product_model.dart';

/// Represents a single item in the cart.
class CartItem {
  const CartItem({
    this.id,
    required this.product,
    this.quantity = 1,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final ProductModel product;
  final int quantity;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get subtotal => (product.displayPrice > 0 ? product.displayPrice : product.price) * quantity;

  /// Whether this item can be purchased directly (fixed price or "both" with buyNow).
  bool get isFixedPrice =>
      product.sellingType == SellingType.fixedPrice ||
      (product.sellingType == SellingType.both && product.buyNowEnabled);

  /// Whether this item is auction-only.
  bool get isAuction =>
      product.sellingType == SellingType.auction ||
      (product.sellingType == SellingType.both && !product.buyNowEnabled);

  CartItem copyWith({
    String? id,
    ProductModel? product,
    int? quantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CartItem(
        id: id ?? this.id,
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Provider managing the buyer's cart, backed by Supabase `cart_items` table
/// with local state for immediate responsiveness and offline resilience.
class CartProvider extends ChangeNotifier {
  CartProvider([this._supabase]);

  final SupabaseService? _supabase;
  final List<CartItem> _items = [];
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;

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
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isInCart(String productId) =>
      _items.any((i) => i.product.id == productId);

  double get subtotal =>
      fixedPriceItems.fold(0.0, (sum, item) => sum + item.subtotal);

  double get shippingFee => fixedPriceItems.isEmpty ? 0 : 80.0;

  double get platformFee => subtotal * 0.02;

  double get total => subtotal + shippingFee + platformFee;

  /// Called by `_SessionBindings` when the user session becomes active or changes.
  Future<void> startForUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _userId = null;
      _items.clear();
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (_userId == userId && _items.isNotEmpty) return;

    _userId = userId;
    await refresh();
  }

  /// Reloads cart items from Supabase `cart_items`.
  Future<void> refresh() async {
    final userId = _userId;
    final supabase = _supabase;
    if (userId == null || supabase == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Fetch seller profiles for mapping shop badges
      final Map<String, Map<String, dynamic>> sellerProfilesMap = {};
      try {
        final spResponse = await supabase.client
            .from('seller_profiles')
            .select('*, user:user_public_profiles(*)');
        final spRows = spResponse as List<dynamic>;
        for (final sp in spRows) {
          if (sp is Map<String, dynamic> && sp['seller_id'] != null) {
            sellerProfilesMap[sp['seller_id'] as String] = sp;
          }
        }
      } catch (e) {
        debugPrint('CartProvider: seller_profiles fetch error ($e)');
      }

      // 2. Query cart_items joined with product details
      final response = await supabase.client
          .from('cart_items')
          .select('''
            cart_item_id,
            product_id,
            quantity,
            created_at,
            updated_at,
            product:products (
              *,
              seller:user_public_profiles (
                user_id,
                username,
                full_name,
                avatar,
                rating_average,
                trust_score,
                role
              ),
              images:product_images (
                image_url,
                is_primary,
                display_order
              ),
              category:categories (
                category_name
              ),
              auctions (
                auction_id,
                starting_price,
                minimum_increment,
                current_price,
                starts_at,
                ends_at,
                status
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final rows = response as List<dynamic>;
      final fetched = <CartItem>[];

      for (final r in rows) {
        final rowMap = r as Map<String, dynamic>;
        final productMap = rowMap['product'] as Map<String, dynamic>?;
        if (productMap == null) continue;

        final sellerId = productMap['seller_id'] as String?;
        final product = ProductModel.fromSupabase(
          productMap,
          sellerProfile: sellerId != null ? sellerProfilesMap[sellerId] : null,
        );

        fetched.add(CartItem(
          id: rowMap['cart_item_id'] as String?,
          product: product,
          quantity: (rowMap['quantity'] as num?)?.toInt() ?? 1,
          createdAt: rowMap['created_at'] != null
              ? DateTime.tryParse(rowMap['created_at'] as String)
              : null,
          updatedAt: rowMap['updated_at'] != null
              ? DateTime.tryParse(rowMap['updated_at'] as String)
              : null,
        ));
      }

      _items.clear();
      _items.addAll(fetched);
    } catch (e) {
      debugPrint('CartProvider.refresh error ($e)');
      // Non-fatal: keep any local items
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a product to the cart and persists to Supabase database.
  Future<void> addToCart(ProductModel product, {int quantity = 1}) async {
    final index = _items.indexWhere((i) => i.product.id == product.id);
    final targetQuantity = index >= 0 ? _items[index].quantity + quantity : quantity;

    if (index >= 0) {
      _items[index] = _items[index].copyWith(quantity: targetQuantity);
    } else {
      _items.add(CartItem(product: product, quantity: targetQuantity));
    }
    notifyListeners();

    // Persist to Supabase if authenticated
    final userId = _userId;
    final supabase = _supabase;
    if (userId != null && supabase != null) {
      try {
        await supabase.client.from('cart_items').upsert({
          'user_id': userId,
          'product_id': product.id,
          'quantity': targetQuantity,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,product_id');
      } catch (e) {
        debugPrint('CartProvider.addToCart Supabase error: $e');
      }
    }
  }

  /// Removes an item from the cart and database.
  Future<void> removeFromCart(String productId) async {
    _items.removeWhere((i) => i.product.id == productId);
    notifyListeners();

    final userId = _userId;
    final supabase = _supabase;
    if (userId != null && supabase != null) {
      try {
        await supabase.client
            .from('cart_items')
            .delete()
            .eq('user_id', userId)
            .eq('product_id', productId);
      } catch (e) {
        debugPrint('CartProvider.removeFromCart Supabase error: $e');
      }
    }
  }

  /// Updates quantity in memory and in the database.
  Future<void> updateQuantity(String productId, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(productId);
      return;
    }
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      notifyListeners();

      final userId = _userId;
      final supabase = _supabase;
      if (userId != null && supabase != null) {
        try {
          await supabase.client
              .from('cart_items')
              .update({
                'quantity': quantity,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('user_id', userId)
              .eq('product_id', productId);
        } catch (e) {
          debugPrint('CartProvider.updateQuantity Supabase error: $e');
        }
      }
    }
  }

  /// Clears all cart items locally and from the database.
  Future<void> clearCart() async {
    _items.clear();
    notifyListeners();

    final userId = _userId;
    final supabase = _supabase;
    if (userId != null && supabase != null) {
      try {
        await supabase.client
            .from('cart_items')
            .delete()
            .eq('user_id', userId);
      } catch (e) {
        debugPrint('CartProvider.clearCart Supabase error: $e');
      }
    }
  }

  void clearFixedPriceItems() {
    final fixedIds = fixedPriceItems.map((i) => i.product.id).toList();
    _items.removeWhere((i) => i.isFixedPrice);
    notifyListeners();

    final userId = _userId;
    final supabase = _supabase;
    if (userId != null && supabase != null && fixedIds.isNotEmpty) {
      try {
        supabase.client
            .from('cart_items')
            .delete()
            .eq('user_id', userId)
            .inFilter('product_id', fixedIds);
      } catch (e) {
        debugPrint('CartProvider.clearFixedPriceItems Supabase error: $e');
      }
    }
  }
}
