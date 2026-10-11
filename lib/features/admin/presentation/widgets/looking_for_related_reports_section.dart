import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../data/looking_for_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';

class LookingForRelatedReportsSection extends StatelessWidget {
  const LookingForRelatedReportsSection({
    super.key,
    required this.currentReportId,
    required this.reports,
  });

  final String currentReportId;
  final List<LookingForAdminReport> reports;

  @override
  Widget build(BuildContext context) {
    if (reports.length <= 1) return const SizedBox.shrink();

    return AdminDisputeModalSection(
      title: 'Related reports on this post',
      subtitle:
          'Confirming a violation closes all open reports once without duplicate strikes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in reports)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: r.id == currentReportId
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lookingForReportReasonLabel(r.reason) ?? r.reason,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Reporter: ${r.reporterName}'
                        '${r.id == currentReportId ? ' (this case)' : ''}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
