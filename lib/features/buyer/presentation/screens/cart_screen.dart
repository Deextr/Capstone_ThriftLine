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
import '../../data/order_query.dart';
import '../widgets/awaiting_payment_tile.dart';
import '../widgets/cart_checkout_shop_section.dart';

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
    final supabase = context.read<SupabaseService>();
    await restoreAbandonedFixedPriceCheckouts(supabase);
    await syncMyUnpaidCheckouts(supabase);
    if (!mounted) return;
    final cart = context.read<CartProvider>();
    await cart.refresh();
    if (!mounted) return;
    final buyerId = context.read<AuthProvider>().user?.id;
    if (buyerId == null) {
      setState(() => _awaiting = []);
      return;
    }
    try {
      final orders = await fetchOrdersForBuyer(supabase, buyerId);
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

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.buyerHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final items = cart.fixedPriceItems;
    final selected = cart.selectedItems;
    final shops = cart.shopGroups;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
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
            onPressed: _handleBack,
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
                                'Auction payment due',
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
                              'Auction payment due',
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
                            CartCheckoutShopSection(
                              shop: shop,
                              mode: CartLineInteractionMode.cart,
                              cart: cart,
                            ),
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
