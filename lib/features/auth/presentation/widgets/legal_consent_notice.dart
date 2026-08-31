import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../domain/legal_documents.dart';

/// Text-based legal agreement notice used on the Login and Sign Up screens.
///
/// Continuing (email or Google sign-in) records consent. The document names
/// open the existing [LegalDocumentScreen] viewers.
class LegalConsentNotice extends StatefulWidget {
  const LegalConsentNotice({
    super.key,
    this.textColor,
    this.linkColor,
  });

  final Color? textColor;
  final Color? linkColor;

  @override
  State<LegalConsentNotice> createState() => _LegalConsentNoticeState();
}

class _LegalConsentNoticeState extends State<LegalConsentNotice> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocumentType.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocumentType.privacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  void _openDocument(LegalDocumentType type) {
    context.push(RouteNames.legalDocument(type));
  }

  @override
  Widget build(BuildContext context) {
    final bodyColor = widget.textColor ?? Colors.white.withValues(alpha: 0.86);
    final linkColor = widget.linkColor ?? AppColors.primaryLight;
    final baseStyle = AppTypography.body.copyWith(
      fontSize: 13,
      height: 1.45,
      color: bodyColor,
    );
    final linkStyle = baseStyle.copyWith(
      color: linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms and Conditions',
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
