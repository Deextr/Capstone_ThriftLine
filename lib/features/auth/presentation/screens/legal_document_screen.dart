import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../domain/legal_documents.dart';

/// Full-screen reader for Terms and Conditions, Privacy Policy, About, or FAQ.
///
/// Reachable before sign-in so consent can be given from an informed position,
/// as well as from the buyer and seller profile tabs and settings.
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final auth = context.read<AuthProvider>();
              context.go(
                auth.isAuthenticated ? auth.homeRoute : RouteNames.login,
              );
            }
          },
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
