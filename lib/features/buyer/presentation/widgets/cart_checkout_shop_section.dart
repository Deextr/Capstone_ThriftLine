import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/cart_provider.dart';
import '../../data/cart_shop_group.dart';

import 'order_cost_breakdown_section.dart';

/// Interactive cart editing vs read-only checkout review for the same line layout.
enum CartLineInteractionMode { cart, checkoutReview }

class CartCheckoutShopSection extends StatelessWidget {
  const CartCheckoutShopSection({
    super.key,
    required this.shop,
    required this.mode,
    this.cart,
    this.orderIndex,
    this.totalOrders,
  });

  final CartShopGroup shop;
  final CartLineInteractionMode mode;
  final CartProvider? cart;
  final int? orderIndex;
  final int? totalOrders;

  @override
  Widget build(BuildContext context) {
    final cartProvider = mode == CartLineInteractionMode.cart
        ? (cart ?? context.read<CartProvider>())
        : null;
    final shopState = mode == CartLineInteractionMode.cart
        ? cartProvider!.shopCheckboxValue(shop.sellerKey)
        : null;

    final isReview = mode == CartLineInteractionMode.checkoutReview;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                mode == CartLineInteractionMode.cart ? 4 : 14,
                10,
                14,
                10,
              ),
              child: Row(
                children: [
                  if (mode == CartLineInteractionMode.cart) ...[
                    Checkbox(
                      tristate: true,
                      value: shopState,
                      activeColor: AppColors.primary,
                      onChanged: (_) => cartProvider!.setShopSelected(
                        shop.sellerKey,
                        shopState != true,
                      ),
                    ),
                  ],
                  const Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shop.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subheading.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (shop.sellerVerified && !isReview) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                  if (isReview &&
                      totalOrders != null &&
                      totalOrders! > 1 &&
                      orderIndex != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Order ${orderIndex! + 1} of $totalOrders',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            for (var i = 0; i < shop.items.length; i++)
              CartCheckoutProductLine(
                item: shop.items[i],
                mode: mode,
                selected: mode == CartLineInteractionMode.cart
                    ? (cartProvider?.isSelected(shop.items[i].product.id) ?? false)
                    : false,
                isLast: i == shop.items.length - 1,
              ),
            if (isReview) ...[
              const Divider(height: 1),
              OrderCostBreakdown(
                subtotal: shop.subtotal,
                shippingFee: shop.shippingFee,
                platformFee: shop.platformFee,
                total: shop.total,
                itemCount: shop.quantity,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CartCheckoutProductLine extends StatelessWidget {
  const CartCheckoutProductLine({
    super.key,
    required this.item,
    required this.mode,
    required this.selected,
    required this.isLast,
  });

  final CartItem item;
  final CartLineInteractionMode mode;
  final bool selected;
  final bool isLast;

  static const double _imageSize = 72;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final readOnly = mode == CartLineInteractionMode.checkoutReview;
    final cart = readOnly ? null : context.read<CartProvider>();
    final unitPrice = product.displayPrice > 0
        ? product.displayPrice
        : product.price;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            readOnly ? 14 : 4,
            10,
            readOnly ? 14 : 10,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!readOnly)
                Checkbox(
                  value: selected,
                  activeColor: AppColors.primary,
                  onChanged: (value) =>
                      cart?.toggleSelected(product.id, value ?? false),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: _imageSize,
                  height: _imageSize,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: _imageSize,
                    height: _imageSize,
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
                    if (product.size != null &&
                        product.size!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Size ${product.size!.trim()}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
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
              if (!readOnly)
                IconButton(
                  onPressed: () => cart?.removeFromCart(product.id),
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
              if (readOnly) ...[
                Text(
                  'Qty ${item.quantity}',
                  style: AppTypography.subheading.copyWith(fontSize: 14),
                ),
              ] else ...[
                if (item.maxPurchasableQuantity > 0)
                  Text(
                    '${item.maxPurchasableQuantity} in stock',
                    style: AppTypography.caption.copyWith(fontSize: 11),
                  ),
                const SizedBox(width: 8),
                _CartQuantityStepper(item: item),
              ],
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 14, endIndent: 14),
      ],
    );
  }
}

class _CartQuantityStepper extends StatelessWidget {
  const _CartQuantityStepper({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final cart = context.read<CartProvider>();

    return Container(
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
                ? () => cart.updateQuantity(product.id, item.quantity - 1)
                : null,
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '${item.quantity}',
                style: AppTypography.subheading.copyWith(fontSize: 14),
              ),
            ),
          ),
          _QtyButton(
            icon: Icons.add_rounded,
            onTap: item.canIncreaseQuantity
                ? () => cart.updateQuantity(product.id, item.quantity + 1)
                : null,
          ),
        ],
      ),
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
