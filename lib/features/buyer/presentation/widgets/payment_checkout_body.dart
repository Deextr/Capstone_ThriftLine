import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/checkout_totals.dart';
import '../../data/paymongo_checkout.dart';
import 'order_cost_breakdown_section.dart';
import 'pay_now_button.dart';
import 'payment_deadline_text.dart';

/// Pending checkout payment UI (post–Continue to Payment).
class PaymentCheckoutBody extends StatelessWidget {
  const PaymentCheckoutBody({
    super.key,
    required this.order,
    this.groupOrders = const [],
    required this.confirming,
    required this.selectedChannel,
    required this.isAbandoning,
    required this.isSavingAddress,
    required this.windowOpen,
    this.returnLabel = '',
    required this.onSelectChannel,
    required this.onChangeAddress,
    this.onReturnToCart,
    this.paymentDueAt,
    this.payOrderId,
  });

  final OrderModel order;
  final String? payOrderId;
  final List<OrderModel> groupOrders;
  final bool confirming;
  final String? selectedChannel;
  final bool isAbandoning;
  final bool isSavingAddress;
  final bool windowOpen;
  final String returnLabel;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback onChangeAddress;
  final VoidCallback? onReturnToCart;
  final DateTime? paymentDueAt;

  bool get _hasValidDeliveryAddress => order.hasValidDeliveryAddress;

  List<OrderModel> get _orders {
    if (groupOrders.isNotEmpty) return groupOrders;
    return [order];
  }

  double get _subtotal => checkoutRoundCurrency(
      _orders.fold<double>(0, (sum, item) => sum + item.amount));
  double get _shipping => checkoutRoundCurrency(
      _orders.fold<double>(0, (sum, item) => sum + item.shippingFee));
  double get _platform => checkoutRoundCurrency(
      _orders.fold<double>(0, (sum, item) => sum + item.platformFee));
  double get _total =>
      checkoutRoundCurrency(_orders.fold<double>(0, (sum, item) => sum + item.total));

  @override
  Widget build(BuildContext context) {
    final totalLabel = formatCurrency(_total);
    final shops = _orders.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (confirming) ...[
                  const _ConfirmingBanner(),
                  const SizedBox(height: 16),
                ],
                _SectionLabel(
                  title: shops > 1 ? 'Your orders' : 'Your order',
                  subtitle: shops > 1
                      ? '$shops orders from $shops shops · Pay once through PayMongo'
                      : '1 order from ${order.sellerName}',
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _orders.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _OrderItemsCard(
                    order: _orders[i],
                    orderIndex: i,
                    totalOrders: shops,
                  ),
                ],
                const SizedBox(height: 16),
                _PaymentAddressSection(
                  order: order,
                  isSavingAddress: isSavingAddress,
                  onChangeAddress: onChangeAddress,
                ),
                const SizedBox(height: 16),
                CombinedPaymentSummaryCard(
                  subtotal: _subtotal,
                  shippingFee: _shipping,
                  platformFee: _platform,
                  total: _total,
                  shopCount: shops,
                  itemCount: _orders.fold<int>(
                    0,
                    (sum, o) =>
                        sum +
                        (o.items.isNotEmpty
                            ? o.items.fold(0, (s, it) => s + it.quantity)
                            : o.quantity),
                  ),
                ),
                if (!confirming) ...[
                  const SizedBox(height: 20),
                  _SectionLabel(
                    title: 'Payment method',
                    subtitle:
                        'Pay securely through PayMongo. Your purchase completes after payment is confirmed.',
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodSelector(
                    selectedChannel: selectedChannel,
                    onSelect: onSelectChannel,
                  ),
                ],
                if (paymentDueAt != null && windowOpen && !confirming) ...[
                  const SizedBox(height: 14),
                  PaymentDeadlineText(due: paymentDueAt!),
                ],
              ],
            ),
          ),
        ),
        _PaymentStickyBar(
          order: order,
          payOrderId: payOrderId,
          totalLabel: totalLabel,
          confirming: confirming,
          selectedChannel: selectedChannel,
          hasAddress: _hasValidDeliveryAddress,
          windowOpen: windowOpen,
          isAbandoning: isAbandoning,
          returnLabel: returnLabel,
          onChangeAddress: onChangeAddress,
          onReturnToCart: onReturnToCart,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.subheading),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmingBanner extends StatelessWidget {
  const _ConfirmingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirming your payment...',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "We're confirming your payment with PayMongo. This can take a few seconds.",
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  const _OrderItemsCard({
    required this.order,
    this.orderIndex,
    this.totalOrders,
  });

  final OrderModel order;
  final int? orderIndex;
  final int? totalOrders;

  @override
  Widget build(BuildContext context) {
    final lines = order.items.isNotEmpty
        ? order.items
        : [
            OrderLineItem(
              id: order.productId,
              productId: order.productId,
              title: order.productTitle,
              imageUrl: order.productImage,
              size: order.size,
              unitPrice: order.amount,
              quantity: order.quantity,
              lineTotal: order.amount,
            ),
          ];

    final totalItemCount = lines.fold<int>(0, (sum, i) => sum + i.quantity);

    return ThriftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subheading.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (order.orderNumber.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '#${order.orderNumber}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (totalOrders != null && totalOrders! > 1 && orderIndex != null) ...[
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _OrderLineRow(item: lines[i]),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          OrderCostBreakdown(
            subtotal: order.amount,
            shippingFee: order.shippingFee,
            platformFee: order.platformFee,
            total: order.total,
            itemCount: totalItemCount,
          ),
        ],
      ),
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({required this.item});

  final OrderLineItem item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl ?? '';
    final detailParts = <String>[
      if (item.size != null && item.size!.trim().isNotEmpty) item.size!.trim(),
      '${item.quantity} × ${formatCurrency(item.unitPrice)}',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductThumbnail(imageUrl: imageUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (detailParts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detailParts.join(' · '),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatCurrency(item.lineTotal),
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: imageUrl.isEmpty
          ? Container(
              width: 64,
              height: 64,
              color: AppColors.surfaceVariant,
              child: const Icon(
                Icons.image_outlined,
                size: 24,
                color: AppColors.textHint,
              ),
            )
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 64,
                height: 64,
                color: AppColors.surfaceVariant,
              ),
              errorWidget: (_, _, _) => Container(
                width: 64,
                height: 64,
                color: AppColors.surfaceVariant,
                child: const Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: AppColors.textHint,
                ),
              ),
            ),
    );
  }
}

class _PaymentAddressSection extends StatelessWidget {
  const _PaymentAddressSection({
    required this.order,
    required this.isSavingAddress,
    required this.onChangeAddress,
  });

  final OrderModel order;
  final bool isSavingAddress;
  final VoidCallback onChangeAddress;

  @override
  Widget build(BuildContext context) {
    final addressText = order.shippingAddress.trim();
    final hasAddress = order.hasValidDeliveryAddress;

    return ThriftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Deliver to', style: AppTypography.subheading),
              ),
              if (isSavingAddress)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else if (hasAddress)
                TextButton(
                  onPressed: onChangeAddress,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Change'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasAddress) ...[
            if (order.addressName?.trim().isNotEmpty == true)
              Text(
                order.addressName!.trim(),
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            if (order.buyerName.isNotEmpty) const SizedBox(height: 2),
            Text(addressText, style: AppTypography.body.copyWith(fontSize: 13)),
          ] else ...[
            Text(
              'Please add a delivery address before proceeding with payment.',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isSavingAddress ? null : onChangeAddress,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add Delivery Address'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selectedChannel,
    required this.onSelect,
  });

  final String? selectedChannel;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < kPaymongoChannels.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _PaymentMethodOption(
            channel: kPaymongoChannels[i],
            selected: selectedChannel == kPaymongoChannels[i],
            onTap: () => onSelect(kPaymongoChannels[i]),
          ),
        ],
      ],
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final String channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = paymongoChannelLabel(channel);
    final subtitle = switch (channel) {
      'gcash' => 'Pay with your GCash wallet',
      'card' => 'Visa, Mastercard, and other major cards',
      _ => 'Pay through PayMongo',
    };
    final icon = switch (channel) {
      'gcash' => Icons.account_balance_wallet_rounded,
      'card' => Icons.credit_card_rounded,
      _ => Icons.payments_outlined,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.45)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primary : AppColors.textHint,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentStickyBar extends StatelessWidget {
  const _PaymentStickyBar({
    required this.order,
    this.payOrderId,
    required this.totalLabel,
    required this.confirming,
    required this.selectedChannel,
    required this.hasAddress,
    required this.windowOpen,
    required this.isAbandoning,
    required this.returnLabel,
    required this.onChangeAddress,
    this.onReturnToCart,
  });

  final OrderModel order;
  final String? payOrderId;
  final String totalLabel;
  final bool confirming;
  final String? selectedChannel;
  final bool hasAddress;
  final bool windowOpen;
  final bool isAbandoning;
  final String returnLabel;
  final VoidCallback onChangeAddress;
  final VoidCallback? onReturnToCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        0,
        12,
        0,
        MediaQuery.paddingOf(context).bottom > 0 ? 0 : 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectedChannel != null && !confirming) ...[
              Row(
                children: [
                  Text(
                    'Pay with',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    paymongoChannelLabel(selectedChannel!),
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    totalLabel,
                    style: AppTypography.subheading.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (confirming)
              const ThriftButton(
                label: 'Confirming your payment...',
                onPressed: null,
                isLoading: true,
              )
            else ...[
              if (!hasAddress)
                ThriftButton(
                  label: 'Add Delivery Address',
                  onPressed: onChangeAddress,
                )
              else if (!windowOpen)
                const ThriftButton(
                  label: 'Payment window ended',
                  onPressed: null,
                )
              else if (selectedChannel == null)
                const ThriftButton(
                  label: 'Select a payment method',
                  onPressed: null,
                )
              else
                PayNowButton(
                  orderId: (payOrderId ?? order.id).trim(),
                  channel: selectedChannel!,
                  amountLabel: totalLabel,
                ),
            ],
            if (!confirming) ...[
              const SizedBox(height: 8),
              Text(
                !hasAddress
                    ? 'Payment is unavailable until you add a delivery address.'
                    : selectedChannel != null && windowOpen
                    ? 'You will continue to PayMongo to complete payment.'
                    : 'Choose a payment method above to continue.',
                style: AppTypography.caption.copyWith(
                  color: !hasAddress
                      ? AppColors.error.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onReturnToCart != null) ...[
              const SizedBox(height: 10),
              ThriftButton(
                label: isAbandoning ? 'Cancelling…' : returnLabel,
                variant: ThriftButtonVariant.outline,
                onPressed: isAbandoning || confirming ? null : onReturnToCart,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
