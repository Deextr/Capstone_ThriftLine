import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/looking_for_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';

class LookingForDisputeHistorySection extends StatelessWidget {
  const LookingForDisputeHistorySection({
    super.key,
    required this.report,
    required this.violations,
    this.expanded = false,
  });

  final LookingForAdminReport report;
  final List<LookingForViolationRecord> violations;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AdminDisputeModalSection(
      title: 'Moderation history',
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            '${report.confirmedViolations} confirmed violation(s) on record',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            'Dismissed or insufficient-evidence reports are not misconduct.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          children: [
            if (violations.isEmpty)
              Text(
                'No prior confirmed Looking For violations for this member.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else
              for (final v in violations.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Strike ${v.strikeNumber}'
                    '${v.postTitle != null ? ' — ${v.postTitle}' : ''}',
                    style: AppTypography.caption,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
