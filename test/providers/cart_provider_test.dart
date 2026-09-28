import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/providers/cart_provider.dart';

ProductModel _product({
  required String id,
  SellingType sellingType = SellingType.fixedPrice,
  int quantityAvailable = 3,
  double price = 100,
  String? sellerId = 'seller-1',
  String sellerName = 'Seller',
}) {
  return ProductModel(
    id: id,
    sellerId: sellerId,
    sellerUsername: 'seller',
    sellerName: sellerName,
    sellerAvatar: '',
    sellerVerified: true,
    title: 'Item $id',
    description: 'A fixed-price listing',
    price: price,
    category: ProductCategory.tops,
    condition: ProductCondition.good,
    createdAt: DateTime.utc(2026, 9, 28),
    quantityAvailable: quantityAvailable,
    sellingType: sellingType,
  );
}

void main() {
  test('adding the same fixed-price product updates quantity', () async {
    final cart = CartProvider();
    final product = _product(id: 'p1', quantityAvailable: 5);

    await cart.addToCart(product);
    await cart.addToCart(product, quantity: 2);

    expect(cart.items, hasLength(1));
    expect(cart.items.single.quantity, 3);
    expect(cart.errorMessage, isNull);
    expect(cart.selectedSubtotal, 300);
  });

  test('quantity cannot exceed available stock', () async {
    final cart = CartProvider();
    final product = _product(id: 'p1', quantityAvailable: 2);

    await cart.addToCart(product, quantity: 5);

    expect(cart.items.single.quantity, 2);
    expect(cart.errorMessage, contains('Only 2 available'));
  });

  test('auction listings are not added to the cart', () async {
    final cart = CartProvider();

    await cart.addToCart(
      _product(id: 'auction', sellingType: SellingType.auction),
    );

    expect(cart.items, isEmpty);
    expect(cart.errorMessage, contains('Place a bid'));
  });

  test('deselected items are left out of the checkout total', () async {
    final cart = CartProvider();
    await cart.addToCart(_product(id: 'a', price: 40));
    await cart.addToCart(_product(id: 'b', price: 60, sellerId: 'seller-2'));

    cart.toggleSelected('b', false);

    expect(cart.selectedItems.map((item) => item.product.id), ['a']);
    expect(cart.selectedSubtotal, 40);
    expect(cart.isSelected('a'), isTrue);
    expect(cart.isSelected('b'), isFalse);
  });

  test('checkout route keeps Buy Now separate from a multi-item cart', () {
    expect(RouteNames.checkoutFor(productId: 'one'), '/checkout?product=one');
    expect(
      RouteNames.checkoutFor(productIds: ['a', 'b']),
      '/checkout?products=a,b',
    );
  });

  test('cart items are grouped by shop with a shop checkbox', () async {
    final cart = CartProvider();
    await cart.addToCart(
      _product(id: 'shirt', price: 500, sellerName: 'Thrift Shop A'),
    );
    await cart.addToCart(
      _product(id: 'pants', price: 700, sellerName: 'Thrift Shop A'),
    );
    await cart.addToCart(
      _product(
        id: 'jacket',
        price: 900,
        sellerId: 'seller-2',
        sellerName: 'Vintage Shop B',
      ),
    );

    expect(cart.shopGroups.map((shop) => shop.shopName), [
      'Thrift Shop A',
      'Vintage Shop B',
    ]);
    expect(cart.shopGroups.first.items, hasLength(2));
    expect(cart.shopCheckboxValue(cart.shopGroups.first.sellerKey), isTrue);

    cart.toggleSelected('pants', false);
    expect(cart.shopCheckboxValue(cart.shopGroups.first.sellerKey), isNull);

    cart.setShopSelected(cart.shopGroups.first.sellerKey, true);
    expect(cart.isSelected('pants'), isTrue);

    cart.setShopSelected(cart.shopGroups.last.sellerKey, false);
    expect(cart.selectedItems.map((item) => item.product.id), [
      'shirt',
      'pants',
    ]);
    expect(cart.selectedShopGroups, hasLength(1));
    expect(cart.selectedShopGroups.single.subtotal, 1200);
    expect(cart.selectedShopGroups.single.shippingFee, 80);
  });

  test('selected total charges shipping once per shop', () async {
    final cart = CartProvider();
    await cart.addToCart(_product(id: 'a', price: 800, sellerName: 'Shop A'));
    await cart.addToCart(
      _product(id: 'b', price: 700, sellerId: 'seller-2', sellerName: 'Shop B'),
    );

    expect(cart.selectedShopGroups, hasLength(2));
    expect(cart.selectedShippingFee, 160);
    expect(
      cart.selectedTotal,
      cart.selectedSubtotal + 160 + cart.selectedPlatformFee,
    );
  });
}
