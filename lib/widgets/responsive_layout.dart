import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/responsive.dart';

/// Constrains content width on larger screens while staying mobile-first.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.child,
    this.padding,
    this.centerContent = true,
    this.maxWidth = AppConstants.maxContentWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool centerContent;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = padding ?? Responsive.horizontalPadding(context);

    return Padding(
      padding: horizontalPadding,
      child: Align(
        alignment: centerContent ? Alignment.topCenter : Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
