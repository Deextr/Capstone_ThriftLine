import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';

/// Clean, compact financial breakdown for an individual seller/shop order.
///
/// Formula:
/// Order Total = Item Subtotal + Shipping Fee + Platform Fee
class OrderCostBreakdown extends StatelessWidget {
  const OrderCostBreakdown({
    super.key,
    required this.subtotal,
    required this.shippingFee,
    required this.platformFee,
    required this.total,
    this.itemCount,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 12),
    this.backgroundColor,
  });

  final double subtotal;
  final double shippingFee;
  final double platformFee;
  final double total;
  final int? itemCount;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final qtySuffix = itemCount != null
        ? ' ($itemCount ${itemCount == 1 ? 'item' : 'items'})'
        : '';
    final shippingLabel = shippingFee <= 0 ? 'Free' : formatCurrency(shippingFee);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceVariant.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BreakdownRow(
            label: 'Item subtotal$qtySuffix',
            value: formatCurrency(subtotal),
          ),
          const SizedBox(height: 5),
          _BreakdownRow(
            label: 'Shipping fee',
            value: shippingLabel,
            valueColor: shippingFee <= 0 ? AppColors.success : null,
          ),
          if (platformFee > 0) ...[
            const SizedBox(height: 5),
            _BreakdownRow(
              label: 'Platform fee (2%)',
              value: formatCurrency(platformFee),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, thickness: 1),
          ),
          _BreakdownRow(
            label: 'Order total',
            value: formatCurrency(total),
            isTotal: true,
          ),
        ],
      ),
    );
  }
}

/// Final aggregated payment summary card displayed after all seller orders.
///
/// Reconciles:
/// Combined Item Subtotal + Combined Shipping Fees + Combined Platform Fees = Final Payment Amount
/// which also equals the sum of all individual Order Totals.
class CombinedPaymentSummaryCard extends StatelessWidget {
  const CombinedPaymentSummaryCard({
    super.key,
    required this.subtotal,
    required this.shippingFee,
    required this.platformFee,
    required this.total,
    required this.shopCount,
    this.itemCount,
  });

  final double subtotal;
  final double shippingFee;
  final double platformFee;
  final double total;
  final int shopCount;
  final int? itemCount;

  @override
  Widget build(BuildContext context) {
    final subtotalLabel = shopCount > 1 && itemCount != null
        ? 'Items subtotal ($itemCount items, $shopCount shops)'
        : itemCount != null
        ? 'Items subtotal ($itemCount ${itemCount == 1 ? 'item' : 'items'})'
        : 'Items subtotal';

    final shippingLabel = shopCount > 1
        ? 'Shipping fee ($shopCount shops)'
        : 'Shipping fee';

    final shippingValue =
        shippingFee <= 0 ? 'Free' : formatCurrency(shippingFee);

    return ThriftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Payment summary',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (shopCount > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$shopCount shops · 1 payment',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _BreakdownRow(
            label: subtotalLabel,
            value: formatCurrency(subtotal),
          ),
          const SizedBox(height: 8),
          _BreakdownRow(
            label: shippingLabel,
            value: shippingValue,
            valueColor: shippingFee <= 0 ? AppColors.success : null,
          ),
          if (platformFee > 0) ...[
            const SizedBox(height: 8),
            _BreakdownRow(
              label: 'Platform fee (2%)',
              value: formatCurrency(platformFee),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total payment',
                    style: AppTypography.subheading.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Final amount to pay',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                formatCurrency(total),
                style: AppTypography.heading.copyWith(
                  color: AppColors.primaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shopCount > 1
                        ? 'Includes $shopCount orders from $shopCount separate shops. You pay once securely through PayMongo.'
                        : 'Your payment is protected and held in escrow until delivery is confirmed.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
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

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: isTotal
                ? AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  )
                : AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
          ),
        ),
        Text(
          value,
          style: isTotal
              ? AppTypography.subheading.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.primaryDark,
                )
              : AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? AppColors.textPrimary,
                ),
        ),
      ],
    );
  }
}
