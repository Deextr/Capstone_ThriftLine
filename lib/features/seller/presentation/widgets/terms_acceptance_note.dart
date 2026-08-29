import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../auth/domain/legal_documents.dart';

/// Visible acceptance note shown before the seller proceeds from Step 1.
class TermsAcceptanceNote extends StatefulWidget {
  const TermsAcceptanceNote({super.key});

  @override
  State<TermsAcceptanceNote> createState() => _TermsAcceptanceNoteState();
}

class _TermsAcceptanceNoteState extends State<TermsAcceptanceNote> {
  late final TapGestureRecognizer _termsRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => context.push(RouteNames.legalDocument(LegalDocumentType.terms));
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        children: [
          const TextSpan(text: 'By proceeding, you are accepting ThriftLine '),
          TextSpan(
            text: 'Terms and Conditions',
            style: AppTypography.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
