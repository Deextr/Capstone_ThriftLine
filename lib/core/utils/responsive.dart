import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Mobile-first responsive layout utilities.
abstract final class Responsive {
  static double width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isMobile(BuildContext context) =>
      width(context) < AppConstants.breakpointTablet;

  static bool isTablet(BuildContext context) {
    final w = width(context);
    return w >= AppConstants.breakpointTablet &&
        w < AppConstants.breakpointDesktop;
  }

  static bool isDesktop(BuildContext context) =>
      width(context) >= AppConstants.breakpointDesktop;

  /// Returns a value based on the current screen size (mobile-first).
  static T value<T>({
    required BuildContext context,
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }

  /// Scales horizontal padding for larger screens.
  static EdgeInsets horizontalPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: value(
        context: context,
        mobile: AppConstants.spacingMd,
        tablet: AppConstants.spacingXl,
        desktop: AppConstants.spacingXxl,
      ),
    );
  }

  /// Returns responsive column count for grids.
  static int gridColumns(BuildContext context) => value(
        context: context,
        mobile: 2,
        tablet: 3,
        desktop: 4,
      );
}
