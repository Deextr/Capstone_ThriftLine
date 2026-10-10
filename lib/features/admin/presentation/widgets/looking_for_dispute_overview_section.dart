import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/looking_for_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';

class LookingForDisputeOverviewSection extends StatelessWidget {
  const LookingForDisputeOverviewSection({
    super.key,
    required this.report,
    required this.reasonLabel,
  });

  final LookingForAdminReport report;
  final String reasonLabel;

  @override
  Widget build(BuildContext context) {
    final explanation = report.details.trim();

    return AdminDisputeModalSection(
      title: 'Report information',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reasonLabel,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            height: 1.25,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Reporter allegation — not a confirmed violation',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Reported',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        formatAdminTableDateTime(report.createdAt),
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (explanation.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  explanation,
                  style: AppTypography.body.copyWith(
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.border),
              ),
              AdminDisputeKeyValueGrid(
                rows: [
                  ('Reporter', report.reporterName),
                  ('Post author', report.reportedName),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
