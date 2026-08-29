import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../domain/legal_documents.dart';

/// Full-screen reader for the Terms and Conditions or the Privacy Policy.
///
/// Reachable before sign-in so consent can be given from an informed position.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final document = LegalDocuments.byType(type);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(document.title, style: AppTypography.subheading),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(RouteNames.login),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          children: [
            Text(
              document.summary,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'Version ${LegalDocuments.version} · '
              'Last updated ${LegalDocuments.lastUpdated}',
              style: AppTypography.caption.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            for (final section in document.sections) ...[
              Text(section.heading, style: AppTypography.subheading),
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                section.body,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: AppConstants.spacingLg),
            ],
            const SizedBox(height: AppConstants.spacingXl),
          ],
        ),
      ),
    );
  }
}
