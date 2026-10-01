import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_gradients.dart';

class OnboardingIndicator extends StatelessWidget {
  const OnboardingIndicator({
    super.key,
    required this.count,
    required this.currentIndex,
    this.activeColor,
    this.inactiveColor,
  });

  final int count;
  final int currentIndex;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final inactive = inactiveColor ?? Theme.of(context).colorScheme.outline;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            gradient: isActive && activeColor == null
                ? AppGradients.buttonGradient
                : null,
            color: isActive ? activeColor : inactive.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
        );
      }),
    );
  }
}
