import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/seller_order_buckets.dart';

class SellerOrderCard extends StatelessWidget {
  const SellerOrderCard({super.key, required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = sellerOrderChip(order);
    final buyer = shortPersonName(order.buyerName);
    return Semantics(
      button: true,
      label:
          'View order ${order.orderNumber}, ${chip.label}, $buyer, ${formatCurrency(order.total)}',
      child: ThriftCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${order.orderNumber}',
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SellerStatusChip(label: chip.label, variant: chip.variant),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumb(imageUrl: order.productImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productTitle,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qty ${order.quantity}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    buyer,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatCurrency(order.total),
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLine(order),
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'View order',
                  style: AppTypography.label.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _dateLine(OrderModel order) {
  final bucket = sellerOrderBucketFor(order);
  final when = switch (bucket) {
    SellerOrderBucket.shipped =>
      order.shipment?.outForDeliveryAt ??
          order.shipment?.pickedUpAt ??
          order.createdAt,
    SellerOrderBucket.completed =>
      order.shipment?.completedAt ?? order.createdAt,
    _ => order.createdAt,
  };
  final date = formatCompactDate(when);
  return switch (bucket) {
    SellerOrderBucket.pendingPayment => 'Placed $date',
    SellerOrderBucket.toShip => 'Paid $date',
    SellerOrderBucket.shipped => 'Shipped $date',
    SellerOrderBucket.completed => 'Completed $date',
    SellerOrderBucket.cancelled => 'Cancelled $date',
    null => formatCompactDate(order.createdAt),
  };
}

class SellerStatusChip extends StatelessWidget {
  const SellerStatusChip({
    super.key,
    required this.label,
    required this.variant,
  });

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final color = switch (variant) {
      BadgeVariant.primary => AppColors.primaryDark,
      BadgeVariant.secondary => AppColors.secondary,
      BadgeVariant.success => AppColors.success,
      BadgeVariant.error => AppColors.error,
      BadgeVariant.warning => AppColors.secondary,
      BadgeVariant.neutral => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      child: imageUrl.trim().isEmpty
          ? Container(
              width: 56,
              height: 56,
              color: AppColors.surfaceVariant,
              child: const Icon(Icons.image_outlined, size: 22),
            )
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 56,
                height: 56,
                color: AppColors.surfaceVariant,
              ),
              errorWidget: (_, _, _) => Container(
                width: 56,
                height: 56,
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.image_outlined, size: 22),
              ),
            ),
    );
  }
}
