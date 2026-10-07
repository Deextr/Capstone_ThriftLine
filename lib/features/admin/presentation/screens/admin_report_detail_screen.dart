import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_report_decision_content.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_case_detail_widgets.dart';
import '../widgets/admin_order_report_detail_widgets.dart';
import '../widgets/admin_report_decision_widgets.dart';
import '../widgets/admin_review_widgets.dart';
import 'admin_order_report_detail_view.dart';

class AdminReportDetailScreen extends StatelessWidget {
  const AdminReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final report = controller.report;
    final order = controller.relatedOrder;

    if (controller.isLoading) {
      return ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: controller.reportId != null
                  ? const AdminWideCaseDetailSkeleton()
                  : const AdminDetailSkeleton(),
            ),
          ),
        ),
      );
    }

    if (report == null) {
      return AdminCaseDetailPage(
        backLabel: 'Back to reports',
        onBack: () => context.pop(),
        child: AdminErrorState(
          message: controller.errorMessage ?? 'Unable to load this report.',
          onRetry: () => context.read<AdminReportsController>().load(),
        ),
      );
    }

    if (controller.isOrderReport) {
      return AdminOrderReportDetailView(
        report: report,
        order: order,
        controller: controller,
      );
    }

    final kind = adminReportKindOf(
      category: report.category,
      orderId: report.orderId,
    );
    final isOrderLinked = report.orderId != null;

    return AdminCaseDetailPage(
      backLabel: 'Back to reports',
      onBack: () => context.pop(),
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminCaseDetailHeader(
            typeLabel: '$kind report',
            title: reportReasonLabel(report.category),
            status: report.status,
            statusLabel: reportStatusLabel(report.status),
            submittedAt: report.createdAt,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              adminModerationCaseRef(report.id),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          AdminCaseDetailSection(
            first: true,
            title: 'Additional details',
            children: [
              AdminCaseDetailBodyText(
                text: report.details.trim().isNotEmpty
                    ? report.details.trim()
                    : 'No additional details provided.',
              ),
            ],
          ),
          if (isOrderLinked)
            AdminCaseDetailSection(
              title: 'Related order',
              children: [
                AdminCaseDetailField(
                  label: 'Order',
                  value: order != null
                      ? '#${order.orderNumber}'
                      : report.orderNumber == null
                      ? 'Related order'
                      : '#${report.orderNumber}',
                ),
                if ((order?.productTitle ?? report.orderTitle)?.isNotEmpty ==
                    true)
                  AdminCaseDetailField(
                    label: 'Product',
                    value: order?.productTitle ?? report.orderTitle!,
                  ),
                if (order != null) ...[
                  AdminCaseDetailField(
                    label: 'Fulfillment',
                    value: orderStatusLabel(order.status),
                  ),
                  AdminCaseDetailField(
                    label: 'Amount',
                    value: formatCurrency(order.total),
                  ),
                ],
              ],
            ),
          AdminCaseDetailSection(
            title: 'Parties',
            children: [
              AdminCasePartiesRow(
                leftTitle: 'Reporter',
                leftName: report.reporterDisplayName,
                leftLines: [
                  adminHandle(
                    report.reporterUsername,
                    report.reporterDisplayName,
                  ),
                  accountRoleLabel(report.reporterRole),
                ],
                rightTitle: 'Reported user',
                rightName: report.reportedDisplayName,
                rightLines: [
                  adminHandle(
                    report.reportedUsername,
                    report.reportedDisplayName,
                  ),
                  accountRoleLabel(report.reportedRole),
                  if (report.reportedShopName?.trim().isNotEmpty == true)
                    report.reportedShopName!.trim(),
                ],
              ),
            ],
          ),
          AdminCaseDetailSection(
            title: 'Evidence',
            children: [
              AdminEvidenceGallery(
                urls: report.evidence
                    .map((item) => item.signedUrl)
                    .whereType<String>()
                    .where((url) => url.isNotEmpty)
                    .toList(),
              ),
            ],
          ),
          AdminCaseDetailSection(
            title: 'Case history',
            children: [AdminCaseTimeline(events: _reportTimeline(report))],
          ),
          if (canDecideReport(report.status))
            AdminCaseDecisionPanel(
              title: 'Decision',
              lead:
                  'Choose an outcome and message. The reporter will see your response.',
              children: [_DecisionForm(controller: controller)],
            )
          else
            AdminCaseDetailSection(
              title: 'Resolution',
              children: [
                if (report.resolvedAt != null)
                  AdminCaseDetailField(
                    label: 'Closed',
                    value: formatAdminTableDateTime(report.resolvedAt!),
                  ),
                AdminCaseDetailBodyText(
                  text: report.adminResponse?.trim().isNotEmpty == true
                      ? report.adminResponse!.trim()
                      : 'No response was saved.',
                ),
              ],
            ),
        ],
      ),
    );
  }

  static List<AdminCaseTimelineEvent> _reportTimeline(
    CommunityReportModel report,
  ) {
    final events = <AdminCaseTimelineEvent>[
      AdminCaseTimelineEvent(title: 'Report submitted', at: report.createdAt),
    ];
    if (canDecideReport(report.status)) {
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
          title: reportStatusLabel(report.status),
          at: report.resolvedAt,
          isComplete: true,
        ),
      );
    }
    return events;
  }
}

class _DecisionForm extends StatefulWidget {
  const _DecisionForm({required this.controller});

  final AdminReportsController controller;

  @override
  State<_DecisionForm> createState() => _DecisionFormState();
}

class _DecisionFormState extends State<_DecisionForm> {
  String _templateId = kAdminCommunityDecisionTemplates.first.id;

  AdminReportsController get controller => widget.controller;

  void _applyTemplate(AdminResponseTemplate template) {
    setState(() {
      _templateId = template.id;
      if (template.message.isNotEmpty) {
        controller.responseController.text = template.message;
        controller.setResponse(template.message);
      }
    });
  }

  void _syncTemplateWithDecision(String? decision) {
    if (decision == null) return;
    final match = kAdminCommunityDecisionTemplates.where(
      (t) => t.id == decision,
    );
    if (match.isNotEmpty) {
      _applyTemplate(match.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = controller.decision;
    final responseError = controller.response.trim().isEmpty
        ? null
        : adminResponseError(controller.response, decision: selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Action', style: AppTypography.subheading.copyWith(fontSize: 15)),
        const SizedBox(height: 8),
        for (final decision in kAdminReportDecisions)
          AdminDecisionOption(
            value: decision,
            groupValue: selected,
            onChanged: controller.isSaving
                ? (_) {}
                : (value) {
                    context.read<AdminReportsController>().setDecision(value);
                    _syncTemplateWithDecision(value);
                  },
          ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          AdminResponseTemplateDropdown(
            templates: kAdminCommunityDecisionTemplates,
            selectedId: _templateId,
            enabled: !controller.isSaving,
            onSelected: _applyTemplate,
          ),
          const SizedBox(height: 12),
          AdminEditableGeneratedMessage(
            controller: controller.responseController,
            onChanged: context.read<AdminReportsController>().setResponse,
            error: responseError,
          ),
        ],
        const SizedBox(height: 16),
        ThriftButton(
          label: selected == null
              ? 'Choose an action'
              : reportDecisionCta(selected),
          isLoading: controller.isSaving,
          onPressed: controller.canSubmitDecision
              ? () => _confirm(context)
              : null,
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final selected = controller.decision;
    if (selected == null) return;
    final report = controller.report;
    final confirmBody = adminReportDecisionConfirmBody(
      decision: selected,
      orderId: report?.orderId,
    );

    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Confirm decision',
      confirmLabel: reportDecisionCta(selected),
      rows: [
        ('Action', reportDecisionLabel(selected)),
        ('Message', controller.response.trim()),
        ('Details', confirmBody),
      ],
    );
    if (confirmed != true || !context.mounted) return;

    final error = await context.read<AdminReportsController>().submitDecision();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Decision saved.');
  }
}
