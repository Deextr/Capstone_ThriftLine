import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../controllers/admin_looking_for_report_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/looking_for_moderation.dart';
import '../widgets/admin_case_detail_widgets.dart';
import '../widgets/admin_review_widgets.dart';

class AdminLookingForReportDetailScreen extends StatelessWidget {
  const AdminLookingForReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminLookingForReportController>();
    final report = controller.report;

    if (controller.isLoading) {
      return ColoredBox(
        color: AppColors.background,
        child: SafeArea(child: const AdminDetailSkeleton()),
      );
    }

    if (report == null) {
      return AdminCaseDetailPage(
        backLabel: 'Back to disputes',
        onBack: () => context.pop(),
        child: AdminErrorState(
          message: controller.errorMessage ?? 'Unable to load this report.',
          onRetry: () => context.read<AdminLookingForReportController>().load(),
        ),
      );
    }

    final reasonLabel =
        lookingForReportReasonLabel(report.reason) ?? report.reason;

    return AdminCaseDetailPage(
      backLabel: 'Back to disputes',
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminCaseDetailHeader(
            typeLabel: 'Looking For',
            title: '$reasonLabel ${adminModerationCaseRef(report.id)}',
            status: report.status,
            statusLabel: lookingForAdminStatusLabel(report.status),
            submittedAt: report.createdAt,
          ),
          AdminCaseDetailSection(
            first: true,
            title: 'Case overview',
            children: [
              AdminCaseDetailField(label: 'Reason', value: reasonLabel),
              if (report.details.trim().isNotEmpty)
                AdminCaseDetailField(
                  label: 'Explanation',
                  value: report.details.trim(),
                  multiline: true,
                ),
              AdminCaseDetailField(
                label: 'Status',
                value: lookingForAdminStatusLabel(report.status),
              ),
            ],
          ),
          AdminCaseDetailSection(
            title: 'Reported request',
            children: [
              AdminCaseDetailField(label: 'Title', value: report.postTitle),
              if (report.postDescription.trim().isNotEmpty)
                AdminCaseDetailField(
                  label: 'Description',
                  value: report.postDescription.trim(),
                  multiline: true,
                ),
              AdminCaseDetailField(
                label: 'Lifecycle',
                value: report.lifecycleLabel(controller.serverNow),
              ),
              if (report.postCreatedAt != null)
                AdminCaseDetailField(
                  label: 'Posted',
                  value: formatAdminTableDateTime(report.postCreatedAt!),
                ),
              if (report.imageUrl != null && report.imageUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AdminEvidenceGallery(urls: [report.imageUrl!]),
                ),
            ],
          ),
          AdminCaseDetailSection(
            title: 'Parties involved',
            children: [
              AdminCasePartiesRow(
                leftTitle: 'Reporter',
                leftName: report.reporterName,
                leftLines: [
                  adminHandle(report.reporterUsername, report.reporterName),
                  accountRoleLabel(report.reporterRole),
                ],
                rightTitle: 'Reported user',
                rightName: report.reportedName,
                rightLines: [
                  adminHandle(report.reportedUsername, report.reportedName),
                  accountRoleLabel(report.reportedRole),
                  'Prior strikes: ${report.confirmedViolations}',
                ],
              ),
            ],
          ),
          if (controller.violations.isNotEmpty)
            AdminCaseDetailSection(
              title: 'Confirmed violations',
              children: [
                for (final item in controller.violations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Strike ${item.strikeNumber} · ${item.postTitle ?? 'Request'} · ${formatAdminTableDateTime(item.createdAt)}',
                      style: AppTypography.body.copyWith(fontSize: 13),
                    ),
                  ),
              ],
            ),
          AdminCaseDetailSection(
            title: 'Case activity',
            children: [AdminCaseTimeline(events: _lookingForTimeline(report))],
          ),
          if (report.canDecide)
            AdminCaseDecisionPanel(
              title: 'Admin decision',
              lead:
                  'Request more evidence, resolve the case, or dismiss. '
                  'Check “Confirm violation” when resolving if the post broke rules.',
              children: [
                for (final decision in kAdminReportDecisions)
                  AdminDecisionOption(
                    value: decision,
                    groupValue: controller.decision,
                    onChanged: controller.isSaving
                        ? (_) {}
                        : context
                              .read<AdminLookingForReportController>()
                              .setDecision,
                  ),
                if (controller.decision == 'resolved') ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.violationConfirmed,
                    onChanged: controller.isSaving
                        ? null
                        : (v) => context
                              .read<AdminLookingForReportController>()
                              .setViolationConfirmed(v ?? false),
                    title: Text(
                      'Confirm violation (remove post and apply strike rules)',
                      style: AppTypography.body.copyWith(fontSize: 14),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 12),
                ThriftTextField(
                  label: 'Response to reporter',
                  hint: 'The reporter will see this.',
                  controller: controller.responseController,
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                ThriftButton(
                  label: controller.decision == null
                      ? 'Save decision'
                      : reportDecisionCta(controller.decision!),
                  isLoading: controller.isSaving,
                  onPressed: controller.canSubmitDecision
                      ? () => _submitDecision(context)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static List<AdminCaseTimelineEvent> _lookingForTimeline(
    LookingForAdminReport report,
  ) {
    final events = <AdminCaseTimelineEvent>[
      AdminCaseTimelineEvent(title: 'Report submitted', at: report.createdAt),
    ];
    if (report.canDecide) {
      events.add(
        const AdminCaseTimelineEvent(
          title: 'Awaiting admin decision',
          isComplete: false,
          isCurrent: true,
        ),
      );
    } else {
      events.add(
        AdminCaseTimelineEvent(
          title: lookingForAdminStatusLabel(report.status),
          isComplete: true,
        ),
      );
    }
    return events;
  }

  Future<void> _submitDecision(BuildContext context) async {
    final error = await context
        .read<AdminLookingForReportController>()
        .submitDecision();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Decision saved.');
  }
}
