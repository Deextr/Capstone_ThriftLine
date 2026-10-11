import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../controllers/admin_looking_for_report_controller.dart';
import '../../data/looking_for_moderation.dart';
import '../../data/admin_report_decision_content.dart';
import '../../data/admin_review_rules.dart';
import '../../data/looking_for_moderation_decision_content.dart';
import 'admin_case_detail_widgets.dart';
import 'admin_dispute_review_modal_shell.dart';
import 'admin_report_decision_widgets.dart';
import 'community_dispute_decision_cards.dart';
import 'looking_for_dispute_case_overview_section.dart';
import 'looking_for_dispute_evidence_section.dart';
import 'looking_for_dispute_history_section.dart';
import 'looking_for_dispute_overview_section.dart';
import 'looking_for_related_reports_section.dart';

Future<bool?> showLookingForDisputeReviewModal({
  required BuildContext context,
  required String reportId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => ChangeNotifierProvider(
      create: (ctx) => AdminLookingForReportController(
        supabase: ctx.read<SupabaseService>(),
        reportId: reportId,
      ),
      child: LookingForDisputeReviewModal(reportId: reportId),
    ),
  );
}

class LookingForDisputeReviewModal extends StatefulWidget {
  const LookingForDisputeReviewModal({super.key, required this.reportId});

  final String reportId;

  @override
  State<LookingForDisputeReviewModal> createState() =>
      _LookingForDisputeReviewModalState();
}

class _LookingForDisputeReviewModalState
    extends State<LookingForDisputeReviewModal> {
  String? _selectedDecision;
  String? _selectedReasonTemplateId;

  void _onSelectDecision(AdminLookingForReportController controller, String d) {
    if (controller.isSaving) return;
    final templates = lookingForDecisionReasonTemplates(d);
    final preset = templates.firstWhere(
      (t) => t.message.isNotEmpty,
      orElse: () => templates.first,
    );
    setState(() {
      _selectedDecision = d;
      _selectedReasonTemplateId = preset.id;
      controller.setDecision(d);
      controller.responseController.text = preset.message;
    });
  }

  void _applyReasonTemplate(AdminResponseTemplate template) {
    setState(() {
      _selectedReasonTemplateId = template.id;
      if (template.message.isNotEmpty) {
        context
                .read<AdminLookingForReportController>()
                .responseController
                .text =
            template.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminLookingForReportController>();
    final report = controller.report;
    final reasonLabel = report != null
        ? (lookingForReportReasonLabel(report.reason) ?? report.reason)
        : '';

    return AdminDisputeReviewModalShell(
      title: 'Looking For Dispute Review',
      caseRef: report != null ? adminModerationCaseRef(report.id) : null,
      status: report?.status,
      isLoading: controller.isLoading,
      errorMessage: controller.errorMessage,
      onRetry: () => context.read<AdminLookingForReportController>().load(),
      onClose: () => Navigator.of(context).pop(false),
      body: report == null
          ? const SizedBox.shrink()
          : _LookingForDisputeBody(
              report: report,
              reasonLabel: reasonLabel,
              controller: controller,
              selectedDecision: _selectedDecision,
              selectedReasonTemplateId: _selectedReasonTemplateId,
              onSelectDecision: (d) => _onSelectDecision(controller, d),
              onApplyReasonTemplate: _applyReasonTemplate,
            ),
      footer: report != null && report.canDecide
          ? _LookingForFooter(
              controller: controller,
              selectedDecision: _selectedDecision,
              onSubmitted: () => Navigator.of(context).pop(true),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                ),
              ),
            ),
    );
  }
}

class _LookingForDisputeBody extends StatelessWidget {
  const _LookingForDisputeBody({
    required this.report,
    required this.reasonLabel,
    required this.controller,
    required this.selectedDecision,
    required this.selectedReasonTemplateId,
    required this.onSelectDecision,
    required this.onApplyReasonTemplate,
  });

  final LookingForAdminReport report;
  final String reasonLabel;
  final AdminLookingForReportController controller;
  final String? selectedDecision;
  final String? selectedReasonTemplateId;
  final ValueChanged<String> onSelectDecision;
  final ValueChanged<AdminResponseTemplate> onApplyReasonTemplate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LookingForDisputeCaseOverviewSection(
            report: report,
            reasonLabel: reasonLabel,
            serverNow: controller.serverNow,
          ),
          const SizedBox(height: 22),
          LookingForDisputeOverviewSection(
            report: report,
            reasonLabel: reasonLabel,
          ),
          const SizedBox(height: 22),
          LookingForDisputeEvidenceSection(
            report: report,
            serverNow: controller.serverNow,
          ),
          const SizedBox(height: 22),
          LookingForRelatedReportsSection(
            currentReportId: report.id,
            reports: controller.relatedOpenReports,
          ),
          if (controller.relatedOpenReports.length > 1)
            const SizedBox(height: 22),
          LookingForDisputeHistorySection(
            report: report,
            violations: controller.violations,
          ),
          const SizedBox(height: 22),
          AdminDisputeModalSection(
            title: 'Activity',
            child: AdminCaseTimeline(
              events: _lookingForDisputeTimeline(report),
            ),
          ),
          if (report.canDecide) ...[
            const SizedBox(height: 22),
            _LookingForDecisionPanel(
              controller: controller,
              selectedDecision: selectedDecision,
              selectedReasonTemplateId: selectedReasonTemplateId,
              onSelectDecision: onSelectDecision,
              onApplyReasonTemplate: onApplyReasonTemplate,
            ),
          ],
        ],
      ),
    );
  }
}

class _LookingForDecisionPanel extends StatelessWidget {
  const _LookingForDecisionPanel({
    required this.controller,
    required this.selectedDecision,
    required this.selectedReasonTemplateId,
    required this.onSelectDecision,
    required this.onApplyReasonTemplate,
  });

  final AdminLookingForReportController controller;
  final String? selectedDecision;
  final String? selectedReasonTemplateId;
  final ValueChanged<String> onSelectDecision;
  final ValueChanged<AdminResponseTemplate> onApplyReasonTemplate;

  @override
  Widget build(BuildContext context) {
    final rpc = lookingForDecisionToRpc(selectedDecision);
    final responseError = rpc != null && controller.response.trim().isNotEmpty
        ? adminResponseError(controller.response.trim(), decision: rpc)
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Moderation decision',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Remove the post or dismiss the report after reviewing the content.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 14),
          CommunityDisputeDecisionCardGroup(
            selectedValue: selectedDecision,
            onSelected: onSelectDecision,
            options: kLookingForDisputeDecisionOptions,
          ),
          if (selectedDecision != null) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              'Decision reason',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final templates = lookingForDecisionReasonTemplates(
                  selectedDecision!,
                );
                final ids = templates.map((t) => t.id).toSet();
                final selectedId = ids.contains(selectedReasonTemplateId)
                    ? selectedReasonTemplateId!
                    : templates.first.id;
                return AdminResponseTemplateDropdown(
                  templates: templates,
                  selectedId: selectedId,
                  enabled: !controller.isSaving,
                  onSelected: onApplyReasonTemplate,
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller.responseController,
              enabled: !controller.isSaving,
              maxLines: 4,
              minLines: 3,
              onChanged: controller.onResponseChanged,
              decoration: InputDecoration(
                labelText: 'Message to reporter',
                hintText: 'Edit the selected reason if needed…',
                errorText: responseError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<AdminCaseTimelineEvent> _lookingForDisputeTimeline(
  LookingForAdminReport report,
) {
  final events = <AdminCaseTimelineEvent>[
    AdminCaseTimelineEvent(title: 'Report submitted', at: report.createdAt),
  ];
  if (report.canDecide) {
    events.add(
      const AdminCaseTimelineEvent(
        title: 'Awaiting moderation decision',
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

class _LookingForFooter extends StatelessWidget {
  const _LookingForFooter({
    required this.controller,
    required this.selectedDecision,
    required this.onSubmitted,
  });

  final AdminLookingForReportController controller;
  final String? selectedDecision;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: controller.isSaving
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ThriftButton(
            label: lookingForDisputeActionLabel(selectedDecision),
            isLoading: controller.isSaving,
            expand: false,
            onPressed: controller.canSubmitDecision
                ? () => _confirm(context)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final uiDecision = controller.decision;
    final rpc = controller.rpcDecision;
    if (uiDecision == null || rpc == null) return;

    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: lookingForDisputeConfirmTitle(uiDecision),
      confirmLabel: lookingForDisputeActionLabel(uiDecision),
      destructive: lookingForDecisionRequiresViolation(uiDecision),
      rows: [
        ('Action', lookingForDisputeActionLabel(uiDecision)),
        ('Message', controller.response.trim()),
        ('Details', lookingForDisputeConfirmDetail(uiDecision)),
      ],
    );
    if (confirmed != true || !context.mounted) return;

    final error = await controller.submitDecision();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Moderation decision saved.');
    onSubmitted();
  }
}
