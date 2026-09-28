import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/order_model.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/checkout_controller.dart';
<<<<<<< HEAD
=======
import '../../data/cart_shop_group.dart';
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
import '../widgets/awaiting_payment_tile.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<CartProvider>();
    final checkout = context.watch<CheckoutController>();
<<<<<<< HEAD
    final allItems = checkout.allCartItems;
=======
    final items = checkout.checkoutItems;
    final shops = checkout.checkoutShops;
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
    final awaiting = checkout.awaitingPayment;
    final itemsBySeller = checkout.itemsBySeller;

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
            Text(
              'Checkout',
              style: AppTypography.heading.copyWith(fontSize: 18),
            ),
            Text(
              '${allItems.length} ${allItems.length == 1 ? 'item' : 'items'} in cart',
              style: AppTypography.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: checkout.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : allItems.isEmpty
          ? _EmptyCartState(awaiting: awaiting)
          : Column(
              children: [
                if (awaiting.isNotEmpty)
                  _AwaitingPaymentBanner(awaiting: awaiting),
                if (itemsBySeller.keys.length > 1)
                  _MultiSellerNotice(sellerCount: itemsBySeller.keys.length),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
<<<<<<< HEAD
                    children: [
                      for (final entry in itemsBySeller.entries) ...[
                        _SellerGroupHeader(
                          sellerId: entry.key,
                          items: entry.value,
                          checkout: checkout,
                        ),
                        for (int i = 0; i < entry.value.length; i++)
                          _CartItemCard(
                            item: entry.value[i],
                            isSelected: checkout.isSelected(entry.value[i].product.id),
                            onToggleSelect: () => checkout.toggleItemSelection(entry.value[i].product.id),
                            isLast: i == entry.value.length - 1,
                          ),
                      ],
                    ],
=======
                    itemCount: shops.length,
                    itemBuilder: (context, index) {
                      return _CheckoutShopCard(
                        shop: shops[index],
                        isLast: index == shops.length - 1,
                      );
                    },
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                  ),
                ),
              ],
            ),
      bottomNavigationBar: allItems.isEmpty
          ? null
<<<<<<< HEAD
          : const _CheckoutBottomBar(),
=======
          : _CheckoutBottomBar(shops: shops),
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
    );
  }
}

<<<<<<< HEAD
// ═════════════════════════════════════════════════════════════════════════════
=======
class _CheckoutAddressCard extends StatelessWidget {
  const _CheckoutAddressCard({required this.checkout});

  final CheckoutController checkout;

  @override
  Widget build(BuildContext context) {
    final address = checkout.selectedAddress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery address', style: AppTypography.subheading),
                  const SizedBox(height: 4),
                  Text(
                    address == null
                        ? 'Add a delivery address to place this order.'
                        : '${address.recipientName}\n${address.formatted}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                await context.push(RouteNames.addresses);
                if (context.mounted) await checkout.reloadAddresses();
              },
              child: Text(address == null ? 'Add' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
// Empty State
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState({required this.awaiting});

  final List<OrderModel> awaiting;

  @override
  Widget build(BuildContext context) {
    if (awaiting.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        awaiting.length == 1
                            ? 'You have an unpaid checkout'
                            : 'You have ${awaiting.length} unpaid checkouts',
                        style: AppTypography.subheading.copyWith(
                          fontSize: 13,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pay or cancel to continue shopping.',
                  style: AppTypography.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final order in awaiting) AwaitingPaymentTile(order: order),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing to check out',
            style: AppTypography.subheading.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose items in your cart\nto continue',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go(RouteNames.cart),
            child: const Text('Go to cart'),
          ),
        ],
      ),
    );
  }
}

class _AwaitingPaymentBanner extends StatelessWidget {
  const _AwaitingPaymentBanner({required this.awaiting});

  final List<OrderModel> awaiting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        awaiting.length == 1
                            ? 'You have an unpaid checkout'
                            : 'You have ${awaiting.length} unpaid checkouts',
                        style: AppTypography.subheading.copyWith(
                          fontSize: 13,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pay or cancel before starting a new checkout.',
                  style: AppTypography.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final order in awaiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ThriftCard(
                onTap: () => context.push(RouteNames.paymentForOrder(order.id)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.productTitle,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Order #${order.orderNumber} · ${formatCurrency(order.total)}',
                            style: AppTypography.caption.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Pay now',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Multi-Seller Notice & Header & Selection Circle
// ═════════════════════════════════════════════════════════════════════════════

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({
    required this.isSelected,
    this.isPartial = false,
    required this.onTap,
  });

  final bool isSelected;
  final bool isPartial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? AppColors.primary
              : isPartial
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: (isSelected || isPartial) ? AppColors.primary : AppColors.border,
            width: 2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : isPartial
            ? Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _MultiSellerNotice extends StatelessWidget {
  const _MultiSellerNotice({required this.sellerCount});
  final int sellerCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Items from $sellerCount different shops in cart. Check the item you want to pay for now.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerGroupHeader extends StatelessWidget {
  const _SellerGroupHeader({
    required this.sellerId,
    required this.items,
    required this.checkout,
  });

  final String sellerId;
  final List<CartItem> items;
  final CheckoutController checkout;

  @override
  Widget build(BuildContext context) {
    final firstProduct = items.first.product;
    final sellerName = firstProduct.sellerName;
    final isVerified = firstProduct.sellerVerified;
    final isSelectedSeller = checkout.selectedSellerId == sellerId;
    final allItemsSelected =
        items.every((i) => checkout.isSelected(i.product.id));
    final hasAnySelected =
        items.any((i) => checkout.isSelected(i.product.id));

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: InkWell(
        onTap: () => checkout.toggleSellerSelection(sellerId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelectedSeller
                ? AppColors.primary.withValues(alpha: 0.07)
                : AppColors.surfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelectedSeller
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              _SelectionCircle(
                isSelected: allItemsSelected,
                isPartial: !allItemsSelected && hasAnySelected,
                onTap: () => checkout.toggleSellerSelection(sellerId),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.storefront_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        sellerName.isNotEmpty ? sellerName : 'Shop',
                        style: AppTypography.subheading.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelectedSeller)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Active Shop',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Cart Item Card
// ═════════════════════════════════════════════════════════════════════════════

<<<<<<< HEAD
class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.isSelected,
    required this.onToggleSelect,
    this.isLast = false,
  });

  final CartItem item;
  final bool isSelected;
  final VoidCallback onToggleSelect;
=======
class _CheckoutShopCard extends StatelessWidget {
  const _CheckoutShopCard({required this.shop, this.isLast = false});

  final CartShopGroup shop;
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
<<<<<<< HEAD
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border.withValues(alpha: 0.6),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
=======
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
<<<<<<< HEAD
            // Details row with checkbox
=======
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
<<<<<<< HEAD
                  Padding(
                    padding: const EdgeInsets.only(top: 34),
                    child: _SelectionCircle(
                      isSelected: isSelected,
                      onTap: onToggleSelect,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: onToggleSelect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
=======
                  const Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: AppColors.primary,
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                  ),
                  const SizedBox(width: 8),
                  Expanded(
<<<<<<< HEAD
                    child: GestureDetector(
                      onTap: onToggleSelect,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.brand != null &&
                              product.brand!.isNotEmpty) ...[
                            Text(
                              product.brand!.toUpperCase(),
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: AppColors.textHint,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            product.title,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (product.size != null)
                                _DetailChip(
                                  icon: Icons.straighten_rounded,
                                  label: product.size!,
                                ),
                              _DetailChip(
                                icon: Icons.star_outline_rounded,
                                label: product.condition.label,
                              ),
                              if (product.color != null)
                                _DetailChip(
                                  icon: Icons.palette_outlined,
                                  label: product.color!,
                                ),
                            ],
                          ),
                        ],
                      ),
=======
                    child: Text(
                      shop.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subheading.copyWith(fontSize: 15),
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
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
<<<<<<< HEAD

            const Divider(height: 1, indent: 14, endIndent: 14),

            // Price + Quantity controls
=======
            const Divider(height: 1),
            for (final item in shop.items) _CheckoutLine(item: item),
            const Divider(height: 1),
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
<<<<<<< HEAD
                  Text(
                    formatCurrency(product.price),
                    style: AppTypography.subheading.copyWith(
                      color: AppColors.primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (item.quantity > 1) ...[
                    Text(
                      '  × ${item.quantity}',
                      style: AppTypography.caption.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (item.maxPurchasableQuantity > 0) ...[
                    Text(
                      item.maxPurchasableQuantity == 1
                          ? '1 left'
                          : '${item.maxPurchasableQuantity} left',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StepperButton(
                          icon: Icons.remove_rounded,
                          onTap: item.quantity > 1
                              ? () => cart.updateQuantity(
                                  product.id,
                                  item.quantity - 1,
                                )
                              : null,
                        ),
                        SizedBox(
                          width: 32,
                          child: Center(
                            child: Text(
                              '${item.quantity}',
                              style: AppTypography.subheading.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        _StepperButton(
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
=======
                  _SummaryRow(
                    label: 'Items (${shop.quantity})',
                    value: formatCurrency(shop.subtotal),
                  ),
                  const SizedBox(height: 4),
                  _SummaryRow(
                    label: 'Shipping',
                    value: formatCurrency(shop.shippingFee),
                  ),
                  const SizedBox(height: 4),
                  _SummaryRow(
                    label: 'Platform fee (2%)',
                    value: formatCurrency(shop.platformFee),
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    label: 'Shop total',
                    value: formatCurrency(shop.total),
                    bold: true,
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

<<<<<<< HEAD
// ═════════════════════════════════════════════════════════════════════════════
=======
class _CheckoutLine extends StatelessWidget {
  const _CheckoutLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  '${formatCurrency(product.price)}  x ${item.quantity}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Text(
            formatCurrency(item.subtotal),
            style: AppTypography.subheading.copyWith(
              color: AppColors.primary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
// Bottom Checkout Bar
// ═════════════════════════════════════════════════════════════════════════════

class _CheckoutBottomBar extends StatelessWidget {
<<<<<<< HEAD
  const _CheckoutBottomBar();
=======
  const _CheckoutBottomBar({required this.shops});
  final List<CartShopGroup> shops;
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutController>();
<<<<<<< HEAD
    final subtotal = checkout.subtotal;
    final shipping = checkout.shippingFee;
    final platform = checkout.platformFee;
    final total = checkout.total;
    final hasSelection = checkout.selectedItems.isNotEmpty;
    final otherCount = checkout.remainingOtherSellerCount;
    final blocked = checkout.hasUnpaidCheckouts;
=======
    final itemCount = shops.fold<int>(
      0,
      (sum, shop) => sum + shop.items.length,
    );
    final subtotal = checkoutGroupsSubtotal(shops);
    final shipping = checkoutGroupsShipping(shops);
    final platform = checkoutGroupsPlatformFee(shops);
    final total = checkoutGroupsTotal(shops);
    final canSubmit = checkout.hasAddress && !checkout.isSubmitting;
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)

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
          _SummaryRow(
<<<<<<< HEAD
            label: 'Subtotal (${checkout.selectedCount} ${checkout.selectedCount == 1 ? 'item' : 'items'} selected)',
=======
            label: shops.length > 1
                ? 'Subtotal ($itemCount items, ${shops.length} shops)'
                : 'Subtotal ($itemCount items)',
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
            value: formatCurrency(subtotal),
          ),
          const SizedBox(height: 4),
          _SummaryRow(
            label: 'Shipping',
            value: hasSelection ? formatCurrency(shipping) : '₱0.00',
          ),
          const SizedBox(height: 4),
          _SummaryRow(
            label: 'Platform fee (2%)',
            value: formatCurrency(platform),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _SummaryRow(label: 'Total', value: formatCurrency(total), bold: true),
          const SizedBox(height: 8),
          Text(
<<<<<<< HEAD
            blocked
                ? 'Pay or cancel your existing checkout before starting a new one.'
                : !hasSelection
                ? 'Check the item(s) you want to pay for above.'
                : otherCount > 0
                ? 'Orders are paid per shop. Items from other shops remain in your cart.'
=======
            shops.length > 1
                ? 'Each shop becomes its own order with its own shipping and escrow. You will pay the first shop now; remaining shops stay unpaid until you finish each payment.'
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                : 'Next you will choose Card or GCash and pay through PayMongo. The purchase completes only after payment is confirmed.',
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: blocked ? AppColors.error : null,
            ),
            textAlign: TextAlign.center,
          ),
          if (checkout.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              checkout.errorMessage!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
<<<<<<< HEAD
              onPressed: blocked || !hasSelection || checkout.isSubmitting
                  ? null
                  : () async {
                      if (!checkout.hasAddress) {
                        showThriftSnackBar(
                          context,
                          'Please add a delivery address to continue.',
                        );
                        await context.push(RouteNames.addresses);
                        if (!context.mounted) return;
                        await context.read<CheckoutController>().load();
                        if (!context.mounted) return;
                        if (!context.read<CheckoutController>().hasAddress) {
                          return;
                        }
                      }
                      final leftover = context
                          .read<CheckoutController>()
                          .remainingOtherSellerCount;
=======
              onPressed: canSubmit
                  ? () async {
>>>>>>> 17f9910 (home page of buyer: Enhance the UI)
                      final result = await context
                          .read<CheckoutController>()
                          .placeOrder();
                      if (!context.mounted) return;
                      if (result.error != null) {
                        showThriftSnackBar(
                          context,
                          result.error!,
                          isError: true,
                        );
                        return;
                      }
                      if (result.count > 1) {
                        showThriftSnackBar(
                          context,
                          'Pay this shop now. Other shop orders stay unpaid until you finish each payment.',
                        );
                      }
                      context.go(RouteNames.paymentForOrder(result.orderId!));
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.textHint,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                shadowColor: AppColors.primary.withValues(alpha: 0.3),
              ),
              child: checkout.isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          blocked ? Icons.block_rounded : Icons.lock_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          blocked
                              ? 'Pay existing checkout first'
                              : !hasSelection
                              ? 'Select items to pay'
                              : 'Continue to payment (${formatCurrency(total)})',
                          style: AppTypography.subheading.copyWith(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Helper Widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: bold
              ? AppTypography.subheading.copyWith(fontSize: 15)
              : AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
        ),
        Text(
          value,
          style: bold
              ? AppTypography.subheading.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                )
              : AppTypography.body.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}
