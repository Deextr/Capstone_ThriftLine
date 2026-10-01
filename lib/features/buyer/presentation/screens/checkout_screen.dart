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
import '../widgets/cart_checkout_shop_section.dart';

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
    final reviewShops = checkout.checkoutShops;
    final reviewCount = checkout.selectedCount;
    final awaiting = checkout.awaitingPayment;

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
                reviewCount == 0
                    ? 'Review your order'
                    : '$reviewCount ${reviewCount == 1 ? 'item' : 'items'} to pay',
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
            : reviewCount == 0
            ? _EmptyCheckoutState(awaiting: awaiting)
            : Column(
                children: [
                  if (awaiting.isNotEmpty)
                    _AwaitingPaymentBanner(awaiting: awaiting),
                  if (reviewShops.length > 1)
                    _MultiSellerNotice(sellerCount: reviewShops.length),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'To change items or quantities, go back to your cart.',
                        style: AppTypography.caption.copyWith(fontSize: 11),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        for (final shop in reviewShops)
                          CartCheckoutShopSection(
                            shop: shop,
                            mode: CartLineInteractionMode.checkoutReview,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: reviewCount == 0
            ? null
            : const _CheckoutBottomBar(),
      ),
    );
  }
}

class _EmptyCheckoutState extends StatelessWidget {
  const _EmptyCheckoutState({required this.awaiting});

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
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
              ),
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
            'Nothing to check out',
            style: AppTypography.subheading.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select items in your cart,\nthen proceed to checkout',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => context.go(RouteNames.cart),
            child: const Text('Back to cart'),
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
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
              ),
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
            const Icon(
              Icons.storefront_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Items from $sellerCount shops become separate orders, then you pay once.',
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

class _CheckoutBottomBar extends StatelessWidget {
  const _CheckoutBottomBar();

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutController>();
    final subtotal = checkout.subtotal;
    final shipping = checkout.shippingFee;
    final platform = checkout.platformFee;
    final total = checkout.total;
    final leftover = checkout.remainingOtherSellerCount;
    final blocked = checkout.hasUnpaidCheckouts;
    final itemCount = checkout.selectedCount;
    final shopCount = checkout.checkoutShops.length;

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
            label: shopCount > 1
                ? 'Subtotal ($itemCount items, $shopCount shops)'
                : 'Subtotal ($itemCount ${itemCount == 1 ? 'item' : 'items'})',
            value: formatCurrency(subtotal),
          ),
          const SizedBox(height: 4),
          _SummaryRow(label: 'Shipping', value: formatCurrency(shipping)),
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
                : leftover > 0
                ? '$leftover other ${leftover == 1 ? 'item stays' : 'items stay'} in your cart. Edit them from the cart screen.'
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
              onPressed: blocked || checkout.isSubmitting
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
                      final leftoverCount = context
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
                      if (leftoverCount > 0) {
                        showThriftSnackBar(
                          context,
                          'Other cart items are still in your cart.',
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
