import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/admin_review_rules.dart';
import '../../data/looking_for_moderation.dart';
import '../../domain/looking_for_report_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';

class LookingForDisputeCaseOverviewSection extends StatelessWidget {
  const LookingForDisputeCaseOverviewSection({
    super.key,
    required this.report,
    required this.reasonLabel,
    required this.serverNow,
  });

  final LookingForAdminReport report;
  final String reasonLabel;
  final DateTime serverNow;

  @override
  Widget build(BuildContext context) {
    final expiredPending = lookingForReportExpiredReviewRequired(
      status: report.status,
      expiresAt: report.expiresAt,
      serverNow: serverNow,
    );
    final reviewBand = lookingForReportReviewTargetBand(
      reportCreatedAt: report.createdAt,
      serverNow: serverNow,
    );
    final statusLabel = lookingForModerationStatusDisplayLabel(
      status: report.status,
      expiresAt: report.expiresAt,
      serverNow: serverNow,
    );
    final lifecycleLine = lookingForPostExpiryUrgencyHeadline(
      status: report.status,
      expiresAt: report.expiresAt,
      serverNow: serverNow,
    );

    return AdminDisputeModalSection(
      title: 'Case overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expiredPending) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'This Looking For post expired naturally before moderation was '
                'completed. Although it is no longer publicly visible, a '
                'moderation decision is still required to determine whether a '
                'violation occurred.',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(label: statusLabel, emphasized: expiredPending),
              _Badge(label: lifecycleLine),
              _Badge(label: lookingForReportReviewTargetLabel(reviewBand)),
              if (report.openReportsOnPost > 1)
                _Badge(label: '${report.openReportsOnPost} reports on post'),
            ],
          ),
          const SizedBox(height: 14),
          AdminDisputeKeyValueGrid(
            rows: [
              ('Report ID', adminModerationCaseRef(report.id)),
              ('Report reason', reasonLabel),
              ('Submitted', formatAdminTableDateTime(report.createdAt)),
              ('Post lifecycle', report.lifecycleLabel(serverNow)),
              ('Review target', lookingForReportReviewTargetLabel(reviewBand)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized
            ? AppColors.warning.withValues(alpha: 0.12)
            : AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: emphasized ? AppColors.warning : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: emphasized ? AppColors.warning : AppColors.textSecondary,
        ),
      ),
    );
  }
}
