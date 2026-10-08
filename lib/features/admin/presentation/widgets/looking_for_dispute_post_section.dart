import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/looking_for_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';
import 'admin_review_widgets.dart';

class LookingForDisputePostSection extends StatelessWidget {
  const LookingForDisputePostSection({
    super.key,
    required this.report,
    required this.lifecycleLabel,
  });

  final LookingForAdminReport report;
  final String lifecycleLabel;

  @override
  Widget build(BuildContext context) {
    final title = report.postTitle.trim().isNotEmpty
        ? report.postTitle.trim()
        : 'Untitled request';
    final description = report.postDescription.trim();
    final imageUrl = report.imageUrl?.trim();

    return AdminDisputeModalSection(
      title: 'Reported post',
      subtitle: 'Compare this content against the reporter’s allegation.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PostMetaChip(label: lifecycleLabel),
                  if (report.postCreatedAt != null)
                    _PostMetaChip(
                      label:
                          'Posted ${formatAdminTableDateTime(report.postCreatedAt!)}',
                    ),
                  _PostMetaChip(label: 'By ${report.reportedName}'),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: AppTypography.body.copyWith(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                AdminEvidenceGallery(urls: [imageUrl]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PostMetaChip extends StatelessWidget {
  const _PostMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
