import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/cart_provider.dart';
import '../../data/cart_shop_group.dart';

/// Interactive cart editing vs read-only checkout review for the same line layout.
enum CartLineInteractionMode { cart, checkoutReview }

class CartCheckoutShopSection extends StatelessWidget {
  const CartCheckoutShopSection({
    super.key,
    required this.shop,
    required this.mode,
    this.cart,
  });

  final CartShopGroup shop;
  final CartLineInteractionMode mode;
  final CartProvider? cart;

  @override
  Widget build(BuildContext context) {
    final cartProvider = cart ?? context.read<CartProvider>();
    final shopState = mode == CartLineInteractionMode.cart
        ? cartProvider.shopCheckboxValue(shop.sellerKey)
        : null;

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
              padding: EdgeInsets.fromLTRB(
                mode == CartLineInteractionMode.cart ? 4 : 12,
                4,
                12,
                4,
              ),
              child: Row(
                children: [
                  if (mode == CartLineInteractionMode.cart) ...[
                    Checkbox(
                      tristate: true,
                      value: shopState,
                      activeColor: AppColors.primary,
                      onChanged: (_) => cartProvider.setShopSelected(
                        shop.sellerKey,
                        shopState != true,
                      ),
                    ),
                  ],
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
              CartCheckoutProductLine(
                item: shop.items[i],
                mode: mode,
                selected: mode == CartLineInteractionMode.cart
                    ? cartProvider.isSelected(shop.items[i].product.id)
                    : false,
                isLast: i == shop.items.length - 1,
              ),
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
    final cart = context.read<CartProvider>();
    final unitPrice = product.displayPrice > 0
        ? product.displayPrice
        : product.price;
    final readOnly = mode == CartLineInteractionMode.checkoutReview;

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
                      cart.toggleSelected(product.id, value ?? false),
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
              if (!readOnly)
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
