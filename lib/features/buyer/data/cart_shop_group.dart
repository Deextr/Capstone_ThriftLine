import '../../../core/utils/listing_shipping.dart';
import '../../../providers/cart_provider.dart';
import 'checkout_totals.dart';

class CartShopGroup {
  const CartShopGroup({
    required this.sellerKey,
    required this.shopName,
    required this.sellerUsername,
    required this.sellerVerified,
    required this.items,
  });

  final String sellerKey;
  final String shopName;
  final String sellerUsername;
  final bool sellerVerified;
  final List<CartItem> items;

  int get quantity => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      checkoutRoundCurrency(items.fold(0.0, (sum, item) => sum + item.subtotal));

  double get shippingFee => checkoutRoundCurrency(
        calculateShopFixedShippingPreview(
          cartShippingLinesFromProducts(
            items.map((item) => (product: item.product, quantity: item.quantity)),
          ),
        ),
      );

  double get platformFee => checkoutPlatformFee(subtotal);

  double get total => checkoutTotal(
    subtotal: subtotal,
    shippingFee: shippingFee,
    platformFee: platformFee,
  );
}

String cartSellerKey(CartItem item) {
  final id = item.product.sellerId?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'shop:${item.product.sellerName}';
}

List<CartShopGroup> groupCartItemsByShop(Iterable<CartItem> items) {
  final grouped = <String, List<CartItem>>{};
  final samples = <String, CartItem>{};
  for (final item in items) {
    final key = cartSellerKey(item);
    grouped.putIfAbsent(key, () => []).add(item);
    samples.putIfAbsent(key, () => item);
  }

  final groups = grouped.entries.map((entry) {
    final sample = samples[entry.key]!;
    final name = sample.product.sellerName.trim();
    return CartShopGroup(
      sellerKey: entry.key,
      shopName: name.isEmpty ? 'Shop' : name,
      sellerUsername: sample.product.sellerUsername,
      sellerVerified: sample.product.sellerVerified,
      items: List.unmodifiable(entry.value),
    );
  }).toList();

  groups.sort(
    (a, b) => a.shopName.toLowerCase().compareTo(b.shopName.toLowerCase()),
  );
  return groups;
}

double checkoutGroupsSubtotal(Iterable<CartShopGroup> groups) =>
    checkoutRoundCurrency(groups.fold(0.0, (sum, group) => sum + group.subtotal));

double checkoutGroupsShipping(Iterable<CartShopGroup> groups) =>
    checkoutRoundCurrency(groups.fold(0.0, (sum, group) => sum + group.shippingFee));

double checkoutGroupsPlatformFee(Iterable<CartShopGroup> groups) =>
    checkoutRoundCurrency(groups.fold(0.0, (sum, group) => sum + group.platformFee));

double checkoutGroupsTotal(Iterable<CartShopGroup> groups) =>
    checkoutRoundCurrency(groups.fold(0.0, (sum, group) => sum + group.total));
