import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../data/admin_moderation_queue_service.dart';
import '../../data/admin_review_rules.dart';
import '../../domain/looking_for_report_moderation.dart';
import 'admin_ui_components.dart';

class AdminLookingForQueuePostCell extends StatelessWidget {
  const AdminLookingForQueuePostCell({super.key, required this.row});

  final AdminModerationCaseRow row;

  @override
  Widget build(BuildContext context) {
    final title = row.lfPostTitle?.trim().isNotEmpty == true
        ? row.lfPostTitle!
        : row.summary;
    final openCount = row.lfOpenReports ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.tableBody.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text(
          lookingForReportReasonLabel(row.category) ?? row.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: 4),
        Text(
          [
            adminModerationCaseRef(row.caseId),
            if (openCount > 1) '$openCount reports on post',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class AdminLookingForDisputeStatusCell extends StatelessWidget {
  const AdminLookingForDisputeStatusCell({super.key, required this.row});

  final AdminModerationCaseRow row;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final label = lookingForDisputeStatusTableLabel(row.statusRaw);
    final hint = lookingForDisputeStatusTableHint(
      status: row.statusRaw,
      expiresAt: row.lfExpiresAt,
      serverNow: now,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AdminStatusBadge(status: row.statusRaw, label: label),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: AppColors.warning,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class AdminLookingForPostStatusCell extends StatelessWidget {
  const AdminLookingForPostStatusCell({super.key, required this.row});

  final AdminModerationCaseRow row;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final label = lookingForPostStatusTableLabel(
      disputeStatus: row.statusRaw,
      expiresAt: row.lfExpiresAt,
      serverNow: now,
      decisionOutcome: row.lfDecisionOutcome,
    );
    final expiresAt = row.lfExpiresAt;
    final tooltip = expiresAt != null
        ? 'Expires ${formatAdminTableDateTime(expiresAt.toLocal())}'
        : null;

    final child = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.tableBody.copyWith(
        fontSize: 13,
        color: label.startsWith('Expired') || label.startsWith('Just')
            ? AppColors.textSecondary
            : AppColors.textPrimary,
      ),
    );

    if (tooltip == null) return child;

    return Tooltip(message: tooltip, preferBelow: true, child: child);
  }
}
