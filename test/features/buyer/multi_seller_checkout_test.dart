import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/buyer/controllers/checkout_controller.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/providers/auth_provider.dart';
import 'package:thriftline/providers/cart_provider.dart';

ProductModel _mockProduct({
  required String id,
  required String sellerId,
  required String sellerName,
  required double price,
}) {
  return ProductModel.fromSupabase(
    {
      'product_id': id,
      'seller_id': sellerId,
      'name': 'Item $id',
      'price': price,
      'condition': 'good',
      'listing_type': 'fixed_price',
      'status': 'active',
      'quantity_available': 5,
    },
    sellerProfile: {
      'shop_name': sellerName,
      'is_approved': true,
      'user': {
        'user_id': sellerId,
        'username': sellerName,
      },
    },
  );
}

class _MockAuthProvider extends Fake implements AuthProvider {
  @override
  AuthUser? get user => const AuthUser(
        id: 'test-buyer',
        email: 'test@example.com',
        username: 'testbuyer',
        name: 'Test Buyer',
        role: UserRole.buyer,
        avatarUrl: '',
        location: '',
      );
}

class _TestCartProvider extends CartProvider {
  _TestCartProvider(this._testItems);

  final List<CartItem> _testItems;

  @override
  List<CartItem> get fixedPriceItems => _testItems;

  @override
  Future<void> refresh() async {}
}

void main() {
  group('Multi-seller cart item selection in CheckoutController', () {
    test('groups items by seller and allows selecting items', () {
      final p1 = _mockProduct(id: 'p1', sellerId: 'seller-a', sellerName: 'Shop A', price: 500);
      final p2 = _mockProduct(id: 'p2', sellerId: 'seller-a', sellerName: 'Shop A', price: 300);
      final p3 = _mockProduct(id: 'p3', sellerId: 'seller-b', sellerName: 'Shop B', price: 400);

      final cart = _TestCartProvider([
        CartItem(product: p1, quantity: 1),
        CartItem(product: p2, quantity: 1),
        CartItem(product: p3, quantity: 1),
      ]);

      final controller = CheckoutController(
        supabase: SupabaseService(),
        auth: _MockAuthProvider(),
        cart: cart,
      );

      // All items from all sellers are visible
      expect(controller.allCartItems.length, 3);
      expect(controller.itemsBySeller.keys, containsAll(['seller-a', 'seller-b']));
      expect(controller.itemsBySeller['seller-a']!.length, 2);
      expect(controller.itemsBySeller['seller-b']!.length, 1);

      // By default first seller's items are selected
      expect(controller.selectedSellerId, 'seller-a');
      expect(controller.isSelected('p1'), isTrue);
      expect(controller.isSelected('p2'), isTrue);
      expect(controller.isSelected('p3'), isFalse);

      // Switching selection to Shop B deselects Shop A (per-seller checkout rule)
      controller.toggleItemSelection('p3');
      expect(controller.selectedSellerId, 'seller-b');
      expect(controller.isSelected('p1'), isFalse);
      expect(controller.isSelected('p2'), isFalse);
      expect(controller.isSelected('p3'), isTrue);
      expect(controller.subtotal, 400.0);
      expect(controller.shippingFee, 80.0);
      expect(controller.platformFee, 8.0);
      expect(controller.total, 488.0);

      // Toggling p3 off clears selection
      controller.toggleItemSelection('p3');
      expect(controller.selectedItems.isEmpty, isTrue);
      expect(controller.subtotal, 0.0);
      expect(controller.shippingFee, 0.0);
      expect(controller.total, 0.0);
    });

    test('scoped buyNowProductId pre-selects that specific product', () {
      final p1 = _mockProduct(id: 'p1', sellerId: 'seller-a', sellerName: 'Shop A', price: 500);
      final p2 = _mockProduct(id: 'p2', sellerId: 'seller-b', sellerName: 'Shop B', price: 700);

      final cart = _TestCartProvider([
        CartItem(product: p1, quantity: 1),
        CartItem(product: p2, quantity: 1),
      ]);

      final controller = CheckoutController(
        supabase: SupabaseService(),
        auth: _MockAuthProvider(),
        cart: cart,
        buyNowProductId: 'p2',
      );

      expect(controller.allCartItems.length, 1);
      expect(controller.isSelected('p2'), isTrue);
      expect(controller.isSelected('p1'), isFalse);
      expect(controller.subtotal, 700.0);
    });
  });
}
