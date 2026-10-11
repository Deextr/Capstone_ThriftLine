import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/looking_for_moderation.dart';
import '../../domain/looking_for_report_moderation.dart';
import 'admin_dispute_review_modal_shell.dart';
import 'admin_review_widgets.dart';

class LookingForDisputeEvidenceSection extends StatelessWidget {
  const LookingForDisputeEvidenceSection({
    super.key,
    required this.report,
    required this.serverNow,
  });

  final LookingForAdminReport report;
  final DateTime serverNow;

  @override
  Widget build(BuildContext context) {
    final supabase = context.read<SupabaseService>();
    final snapshotEdited = lookingForSnapshotDiffersFromLive(
      snapshotTitle: report.snapshotTitle,
      snapshotDescription: report.snapshotDescription,
      liveTitle: report.postTitle,
      liveDescription: report.postDescription,
    );
    final snapshotImage =
        lookingForPublicUrlFromStoragePath(
          supabase,
          report.snapshotImagePath,
        ) ??
        report.imageUrl;
    final capturedAt = report.snapshotCapturedAt ?? report.createdAt;

    return AdminDisputeModalSection(
      title: 'Reported content and evidence',
      subtitle: 'Captured at report time for moderation review.',
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
              if (snapshotEdited) ...[
                Text(
                  'The post owner changed the live post after this report. '
                  'You are viewing the report-time snapshot below.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.warning,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                report.displayPostTitle.isNotEmpty
                    ? report.displayPostTitle
                    : 'Untitled request',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
              if (report.displayPostDescription.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  report.displayPostDescription,
                  style: AppTypography.body.copyWith(
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              if (snapshotImage != null && snapshotImage.trim().isNotEmpty) ...[
                SizedBox(height: 14),
                AdminEvidenceGallery(urls: [snapshotImage.trim()]),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.border),
              ),
              AdminDisputeKeyValueGrid(
                rows: [
                  if (report.postCreatedAt != null)
                    (
                      'Date posted',
                      formatAdminTableDateTime(report.postCreatedAt!),
                    ),
                  ('Date reported', formatAdminTableDateTime(report.createdAt)),
                  if (report.expiresAt != null)
                    (
                      'Date expired',
                      formatAdminTableDateTime(report.expiresAt!),
                    ),
                  ('Evidence captured', formatAdminTableDateTime(capturedAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
