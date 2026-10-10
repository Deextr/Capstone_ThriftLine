import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_palette.dart';

/// Shared teal gradients derived from ThriftLine primary `#0D9488`.
///
/// Use these instead of one-off gradient colors so emphasis stays consistent.
abstract final class AppGradients {
  static const Color mid = Color(0xFF14B8A6);
  static const Color deep = Color(0xFF0F766E);
  static const Color deeper = Color(0xFF115E59);
  static const Color mist = Color(0xFFF0FDFA);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primaryDark, AppColors.primary, mid],
    stops: [0.0, 0.52, 1.0],
  );

  static LinearGradient get primaryGradientLight {
    if (AppPalette.current.isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withValues(alpha: 0.28),
          AppColors.primaryDark.withValues(alpha: 0.18),
        ],
      );
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCCFBF1), mist],
    );
  }

  static const LinearGradient primaryGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deeper, AppColors.primaryDark, AppColors.primary],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primaryDark, AppColors.primary, mid],
    stops: [0.0, 0.48, 1.0],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF065F56), AppColors.primary, mid],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient authScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59000000), Color(0x330D9488), Color(0x73000000)],
    stops: [0.0, 0.48, 1.0],
  );

  static const LinearGradient navBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.primary, AppColors.primaryDark],
  );

  static BoxDecoration fill({
    LinearGradient gradient = primaryGradient,
    BorderRadius? borderRadius,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      gradient: gradient,
      borderRadius: borderRadius,
      border: border,
      boxShadow: boxShadow,
    );
  }

  static List<BoxShadow> get emphasisShadow => [
    BoxShadow(
      color: AppColors.primaryDark.withValues(alpha: 0.18),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}

class ThriftGradientBackground extends StatelessWidget {
  const ThriftGradientBackground({
    super.key,
    required this.child,
    this.gradient = AppGradients.heroGradient,
  });

  final Widget child;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}
