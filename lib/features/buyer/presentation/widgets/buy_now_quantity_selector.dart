import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/stock_limits.dart';

/// Quantity stepper for fixed-price Buy Now (product detail / buy-now screen).
class BuyNowQuantitySelector extends StatelessWidget {
  const BuyNowQuantitySelector({
    super.key,
    required this.quantity,
    required this.maxPurchasable,
    required this.onChanged,
  });

  final int quantity;
  final int maxPurchasable;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (maxPurchasable <= 1) {
      return const SizedBox.shrink();
    }

    final clamped = clampCartQuantity(quantity, maxPurchasable);
    final stockLabel = maxPurchasable == 1
        ? '1 piece available'
        : '$maxPurchasable pieces available';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quantity',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                enabled: clamped > 1,
                onPressed: () => onChanged(clamped - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '$clamped',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                enabled: clamped < maxPurchasable,
                onPressed: () => onChanged(clamped + 1),
              ),
              const Spacer(),
              Text(
                stockLabel,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.border.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.primary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
