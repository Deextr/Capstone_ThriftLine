import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    this.onChanged,
    this.readOnly = false,
    this.size = 38,
    this.showSentiment = true,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final bool readOnly;
  final double size;
  final bool showSentiment;

  static const Color activeColor = Color(0xFFF59E0B); // Warm amber
  static const Color inactiveColor = Color(0xFFD1D5DB); // Subtle gray border

  String _sentimentLabel(int rating) => switch (rating) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Very Good',
    5 => 'Excellent',
    _ => 'Tap a star to rate',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: value == 0 ? 'No rating selected' : '$value out of 5 stars',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                _StarTouchTarget(
                  starIndex: i,
                  isSelected: i <= value,
                  readOnly: readOnly || onChanged == null,
                  size: size,
                  onTap: () => onChanged?.call(i),
                ),
            ],
          ),
        ),
        if (showSentiment) ...[
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              _sentimentLabel(value),
              key: ValueKey<int>(value),
              style: AppTypography.caption.copyWith(
                fontSize: 14,
                fontWeight: value > 0 ? FontWeight.w600 : FontWeight.w400,
                color: value > 0 ? activeColor : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StarTouchTarget extends StatelessWidget {
  const _StarTouchTarget({
    required this.starIndex,
    required this.isSelected,
    required this.readOnly,
    required this.size,
    required this.onTap,
  });

  final int starIndex;
  final bool isSelected;
  final bool readOnly;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$starIndex star${starIndex == 1 ? '' : 's'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: readOnly ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(
              isSelected ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: isSelected
                  ? StarRatingInput.activeColor
                  : StarRatingInput.inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}

class StarRatingReadout extends StatelessWidget {
  const StarRatingReadout({
    super.key,
    required this.value,
    this.size = 18,
    this.showNumber = false,
  });

  final double value;
  final double size;
  final bool showNumber;

  static const Color activeColor = Color(0xFFF59E0B);
  static const Color inactiveColor = Color(0xFFD1D5DB);

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
            color: i <= rounded ? activeColor : inactiveColor,
          ),
        if (showNumber) ...[
          const SizedBox(width: 6),
          Text(
            value.toStringAsFixed(1),
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}
