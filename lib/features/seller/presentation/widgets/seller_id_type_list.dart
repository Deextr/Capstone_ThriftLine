import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../domain/seller_id_type.dart';

/// Single-choice list of the IDs ThriftLine accepts.
///
/// Unsupported documents are omitted. The selected value is the only type
/// the capture pipeline is allowed to expect.
class SellerIdTypeList extends StatelessWidget {
  const SellerIdTypeList({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SellerIdType? selected;
  final ValueChanged<SellerIdType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < SellerIdType.values.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _IdTypeRow(
            type: SellerIdType.values[i],
            selected: selected == SellerIdType.values[i],
            onTap: () => onSelected(SellerIdType.values[i]),
          ),
        ],
      ],
    );
  }
}

class _IdTypeRow extends StatelessWidget {
  const _IdTypeRow({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final SellerIdType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textHint;
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.55)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (type.detail != null)
                      Text(
                        type.detail!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
