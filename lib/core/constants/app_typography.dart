import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static final TextStyle _displayBase = GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _headingBase = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _subheadingBase = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _bodyBase = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _captionBase = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _labelBase = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
  static final TextStyle _pageTitleBase = GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );
  static final TextStyle _sectionTitleBase = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static final TextStyle _cardTitleBase = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _tableHeaderBase = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );
  static final TextStyle _tableBodyBase = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _tableBodyMediumBase = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static final TextStyle _badgeBase = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  static final TextStyle _helperBase = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _buttonBase = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static TextStyle get display =>
      _displayBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get heading =>
      _headingBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get subheading =>
      _subheadingBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get body => _bodyBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get caption =>
      _captionBase.copyWith(color: AppColors.textSecondary);

  static TextStyle get label =>
      _labelBase.copyWith(color: AppColors.textSecondary);

  static TextStyle get pageTitle =>
      _pageTitleBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get sectionTitle =>
      _sectionTitleBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get cardTitle =>
      _cardTitleBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get tableHeader =>
      _tableHeaderBase.copyWith(color: AppColors.textSecondary);

  static TextStyle get tableBody =>
      _tableBodyBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get tableBodyMedium =>
      _tableBodyMediumBase.copyWith(color: AppColors.textPrimary);

  static TextStyle get badge => _badgeBase;

  static TextStyle get helper =>
      _helperBase.copyWith(color: AppColors.textSecondary);

  static TextStyle get button => _buttonBase;

  static TextTheme textThemeFor(AppPaletteColors colors) {
    return GoogleFonts.interTextTheme().copyWith(
      displayMedium: _displayBase.copyWith(color: colors.primary),
      headlineMedium: _headingBase.copyWith(color: colors.primary),
      titleMedium: _subheadingBase.copyWith(color: colors.primary),
      bodyMedium: _bodyBase.copyWith(color: colors.primary),
      bodySmall: _captionBase.copyWith(color: colors.secondary),
      labelMedium: _labelBase.copyWith(color: colors.secondary),
    );
  }

  static TextTheme get textTheme => textThemeFor(
    AppPaletteColors(
      primary: AppColors.textPrimary,
      secondary: AppColors.textSecondary,
    ),
  );
}

class AppPaletteColors {
  const AppPaletteColors({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;
}
