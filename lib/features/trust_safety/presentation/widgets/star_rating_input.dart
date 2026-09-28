import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    this.onChanged,
    this.readOnly = false,
    this.size = 32,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final bool readOnly;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value == 0 ? 'No rating selected' : '$value out of 5 stars',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: '$i star${i == 1 ? '' : 's'}',
              onPressed: readOnly || onChanged == null
                  ? null
                  : () => onChanged!(i),
              icon: Icon(
                i <= value ? Icons.star_rounded : Icons.star_border_rounded,
                size: size,
                color: i <= value
                    ? const Color(0xFFF59E0B)
                    : AppColors.textHint,
              ),
            ),
        ],
      ),
    );
  }
}

class StarRatingReadout extends StatelessWidget {
  const StarRatingReadout({
    super.key,
    required this.value,
    this.size = 16,
    this.showNumber = false,
  });

  final double value;
  final double size;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final rounded = value.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rounded ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: i <= rounded ? const Color(0xFFF59E0B) : AppColors.textHint,
          ),
        if (showNumber) ...[
          const SizedBox(width: 6),
          Text(
            value.toStringAsFixed(1),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
