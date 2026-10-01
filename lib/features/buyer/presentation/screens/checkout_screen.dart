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
import '../widgets/awaiting_payment_tile.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.cart);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CartProvider>();
    final checkout = context.watch<CheckoutController>();
    final allItems = checkout.allCartItems;
    final awaiting = checkout.awaitingPayment;
    final itemsBySeller = checkout.itemsBySeller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
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
            onPressed: () => _handleBack(context),
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
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: allItems.isEmpty
            ? null
            : const _CheckoutBottomBar(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
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
                            ? 'You have an auction payment due'
                            : 'You have ${awaiting.length} auction payments due',
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
                  'Pay your auction win before starting a new checkout.',
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
            'Your cart is empty',
            style: AppTypography.subheading.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add items from the shop\nto start checkout',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
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
                            ? 'You have an auction payment due'
                            : 'You have ${awaiting.length} auction payments due',
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
                  'Pay your auction win before starting a new checkout.',
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
                'Items from $sellerCount shops. Selected shops become separate orders, then you pay once.',
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
            color: hasAnySelected
                ? AppColors.primary.withValues(alpha: 0.07)
                : AppColors.surfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasAnySelected
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
              if (hasAnySelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Selected',
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
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final cart = context.read<CartProvider>();

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
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
        ),
        child: Column(
          children: [
            // Details row with checkbox
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  ),
                  const SizedBox(width: 14),

                  // Product info
                  Expanded(
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
                    ),
                  ),

                  // Remove button
                  GestureDetector(
                    onTap: () => cart.removeFromCart(product.id),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, indent: 14, endIndent: 14),

            // Price + Quantity controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
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

// ═════════════════════════════════════════════════════════════════════════════
// Bottom Checkout Bar
// ═════════════════════════════════════════════════════════════════════════════

class _CheckoutBottomBar extends StatelessWidget {
  const _CheckoutBottomBar();

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutController>();
    final subtotal = checkout.subtotal;
    final shipping = checkout.shippingFee;
    final platform = checkout.platformFee;
    final total = checkout.total;
    final hasSelection = checkout.selectedItems.isNotEmpty;
    final otherCount = checkout.remainingOtherSellerCount;
    final blocked = checkout.hasUnpaidCheckouts;

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
            label: 'Subtotal (${checkout.selectedCount} ${checkout.selectedCount == 1 ? 'item' : 'items'} selected)',
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
            blocked
                ? 'Pay your auction win before starting a new checkout.'
                : !hasSelection
                ? 'Check the item(s) you want to pay for above.'
                : otherCount > 0
                ? 'Unselected items stay in your cart. Selected shops become separate orders and one payment.'
                : 'Selected shops become separate orders. You pay once through PayMongo.',
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
              onPressed: blocked || !hasSelection || checkout.isSubmitting
                  ? null
                  : () async {
                      if (!checkout.hasAddress ||
                          !checkout.hasValidDeliveryPhone) {
                        showThriftSnackBar(
                          context,
                          checkout.hasAddress
                              ? 'Edit your delivery address and enter a valid '
                                    'phone contact (09XXXXXXXXX) to continue.'
                              : 'Please add a delivery address to continue.',
                          isError: checkout.hasAddress,
                        );
                        await context.push(
                          RouteNames.addresses,
                          extra: checkout.selectedAddress?.id,
                        );
                        if (!context.mounted) return;
                        await context.read<CheckoutController>().load();
                        if (!context.mounted) return;
                        final updated = context.read<CheckoutController>();
                        if (!updated.hasAddress ||
                            !updated.hasValidDeliveryPhone) {
                          return;
                        }
                      }
                      final leftover = context
                          .read<CheckoutController>()
                          .remainingOtherSellerCount;
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
                      if (leftover > 0) {
                        showThriftSnackBar(
                          context,
                          'Unselected items are still in your cart.',
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
                              ? 'Pay auction win first'
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

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.textPrimary : AppColors.textHint,
        ),
      ),
    );
  }
}

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
