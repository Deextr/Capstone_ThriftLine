import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/stock_limits.dart';
import '../../../../models/order_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/cart_shop_group.dart';
import '../../data/order_query.dart';
import '../widgets/awaiting_payment_tile.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<OrderModel> _awaiting = [];
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final cart = context.read<CartProvider>();
    await cart.refresh();
    if (!mounted) return;
    final buyerId = context.read<AuthProvider>().user?.id;
    if (buyerId == null) {
      setState(() => _awaiting = []);
      return;
    }
    try {
      final orders = await fetchOrdersForBuyer(
        context.read<SupabaseService>(),
        buyerId,
      );
      if (!mounted) return;
      setState(() => _awaiting = buyerAwaitingPayment(orders));
    } catch (_) {
      if (!mounted) return;
      setState(() => _awaiting = []);
    }
  }

  Future<void> _checkout() async {
    if (_checkingOut) return;
    setState(() => _checkingOut = true);
    final cart = context.read<CartProvider>();
    await cart.refresh();
    if (!mounted) return;
    final selected = cart.selectedItems;
    if (selected.isEmpty) {
      setState(() => _checkingOut = false);
      showThriftSnackBar(context, 'Select at least one item.', isError: true);
      return;
    }
    for (final item in selected) {
      final shortage = stockShortageMessage(
        title: item.product.title,
        requested: item.quantity,
        available: item.product.maxPurchasableQuantity,
      );
      if (shortage != null) {
        setState(() => _checkingOut = false);
        showThriftSnackBar(context, shortage, isError: true);
        return;
      }
    }
    final ids = selected.map((item) => item.product.id).toList();
    setState(() => _checkingOut = false);
    context.push(RouteNames.checkoutFor(productIds: ids));
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final items = cart.fixedPriceItems;
    final selected = cart.selectedItems;
    final shops = cart.shopGroups;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text('Cart', style: AppTypography.heading.copyWith(fontSize: 18)),
            Text(
              '${items.length} ${items.length == 1 ? 'item' : 'items'}',
              style: AppTypography.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: cart.isLoading && items.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _reload,
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_awaiting.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(
                              'Payment needed',
                              style: AppTypography.subheading,
                            ),
                          ),
                          for (final order in _awaiting)
                            AwaitingPaymentTile(order: order),
                        ],
                        const SizedBox(height: 80),
                        const _EmptyCart(),
                        if (cart.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              cart.errorMessage!,
                              textAlign: TextAlign.center,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        if (_awaiting.isNotEmpty) ...[
                          Text(
                            'Payment needed',
                            style: AppTypography.subheading,
                          ),
                          const SizedBox(height: 8),
                          for (final order in _awaiting)
                            AwaitingPaymentTile(order: order),
                          const SizedBox(height: 12),
                        ],
                        if (cart.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              cart.errorMessage!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        for (final shop in shops)
                          _ShopGroupCard(shop: shop, cart: cart),
                      ],
                    ),
            ),
      bottomNavigationBar: items.isEmpty
          ? null
          : _CartCheckoutBar(
              itemCount: selected.length,
              shopCount: cart.selectedShopGroups.length,
              subtotal: cart.selectedSubtotal,
              total: cart.selectedTotal,
              busy: _checkingOut,
              onCheckout: selected.isEmpty ? null : _checkout,
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.shopping_cart_outlined,
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your cart is empty',
          style: AppTypography.subheading.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Add fixed-price items from a product page',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ShopGroupCard extends StatelessWidget {
  const _ShopGroupCard({required this.shop, required this.cart});

  final CartShopGroup shop;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final shopState = cart.shopCheckboxValue(shop.sellerKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: shopState,
                    activeColor: AppColors.primary,
                    onChanged: (_) =>
                        cart.setShopSelected(shop.sellerKey, shopState != true),
                  ),
                  const Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shop.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subheading.copyWith(fontSize: 15),
                    ),
                  ),
                  if (shop.sellerVerified)
                    const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (var i = 0; i < shop.items.length; i++)
              _CartLine(
                item: shop.items[i],
                selected: cart.isSelected(shop.items[i].product.id),
                isLast: i == shop.items.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.selected,
    required this.isLast,
  });

  final CartItem item;
  final bool selected;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final cart = context.read<CartProvider>();
    final unitPrice = product.displayPrice > 0
        ? product.displayPrice
        : product.price;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                activeColor: AppColors.primary,
                onChanged: (value) =>
                    cart.toggleSelected(product.id, value ?? false),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatCurrency(unitPrice),
                      style: AppTypography.subheading.copyWith(
                        color: AppColors.primary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => cart.removeFromCart(product.id),
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.error,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            children: [
              Text(
                'Subtotal ${formatCurrency(item.subtotal)}',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (item.maxPurchasableQuantity > 0)
                Text(
                  '${item.maxPurchasableQuantity} in stock',
                  style: AppTypography.caption.copyWith(fontSize: 11),
                ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QtyButton(
                      icon: Icons.remove_rounded,
                      onTap: item.quantity > 1
                          ? () => cart.updateQuantity(
                              product.id,
                              item.quantity - 1,
                            )
                          : null,
                    ),
                    SizedBox(
                      width: 28,
                      child: Center(
                        child: Text(
                          '${item.quantity}',
                          style: AppTypography.subheading.copyWith(
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add_rounded,
                      onTap: item.canIncreaseQuantity
                          ? () => cart.updateQuantity(
                              product.id,
                              item.quantity + 1,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 14, endIndent: 14),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.textPrimary : AppColors.textHint,
        ),
      ),
    );
  }
}

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar({
    required this.itemCount,
    required this.shopCount,
    required this.subtotal,
    required this.total,
    required this.busy,
    required this.onCheckout,
  });

  final int itemCount;
  final int shopCount;
  final double subtotal;
  final double total;
  final bool busy;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shopCount > 1
                    ? 'Subtotal ($itemCount items, $shopCount shops)'
                    : 'Subtotal ($itemCount)',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(formatCurrency(subtotal), style: AppTypography.body),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTypography.subheading),
              Text(
                formatCurrency(total),
                style: AppTypography.subheading.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: busy ? null : onCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.textHint,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Checkout ($itemCount)',
                      style: AppTypography.subheading.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
