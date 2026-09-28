import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReportDetailScreen extends StatelessWidget {
  const AdminReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final report = controller.report;
    final order = controller.relatedOrder;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Report'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const AdminDetailSkeleton()
            : report == null
            ? AdminErrorState(
                message:
                    controller.errorMessage ?? 'Unable to load this report.',
                onRetry: () => context.read<AdminReportsController>().load(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  AdminStatusChip(
                    status: report.status,
                    label: reportStatusLabel(report.status),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reportReasonLabel(report.category),
                    style: AppTypography.heading,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted ${formatCompactDate(report.createdAt)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 28),
                  AdminDetailBlock(
                    label: 'People',
                    children: [
                      AdminPersonBlock(
                        embedded: true,
                        label: 'Reported user',
                        name: report.reportedDisplayName,
                        handle: adminHandle(
                          report.reportedUsername,
                          report.reportedDisplayName,
                        ),
                        role: accountRoleLabel(report.reportedRole),
                        shopName: report.reportedShopName,
                      ),
                      const SizedBox(height: 16),
                      AdminPersonBlock(
                        embedded: true,
                        label: 'Reported by',
                        name: report.reporterDisplayName,
                        handle: adminHandle(
                          report.reporterUsername,
                          report.reporterDisplayName,
                        ),
                        role: accountRoleLabel(report.reporterRole),
                      ),
                    ],
                  ),
                  AdminDetailBlock(
                    label: 'What happened',
                    children: [Text(report.details, style: AppTypography.body)],
                  ),
                  if (report.orderId != null)
                    AdminDetailBlock(
                      label: 'Related order',
                      children: [
                        Text(
                          order != null
                              ? 'Order #${order.orderNumber}'
                              : report.orderNumber == null
                              ? 'Related order'
                              : 'Order #${report.orderNumber}',
                          style: AppTypography.subheading,
                        ),
                        if ((order?.productTitle ?? report.orderTitle)
                                ?.isNotEmpty ==
                            true)
                          Text(
                            order?.productTitle ?? report.orderTitle!,
                            style: AppTypography.body,
                          ),
                        if (order != null)
                          Text(
                            '${orderStatusLabel(order.status)} · ${formatCompactDate(order.createdAt)}',
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  AdminDetailBlock(
                    label: 'Evidence',
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
                  if (canDecideReport(report.status))
                    _DecisionForm(controller: controller)
                  else
                    AdminDetailBlock(
                      label: 'Response',
                      children: [
                        Text(
                          report.adminResponse?.trim().isNotEmpty == true
                              ? report.adminResponse!.trim()
                              : 'No response was saved.',
                          style: AppTypography.body,
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

class _DecisionForm extends StatelessWidget {
  const _DecisionForm({required this.controller});

  final AdminReportsController controller;

  @override
  Widget build(BuildContext context) {
    final responseError = controller.response.trim().isEmpty
        ? null
        : adminResponseError(controller.response);

    final selected = controller.decision;

    return AdminDecisionSection(
      title: 'Decision',
      children: [
        for (final decision in kAdminReportDecisions)
          AdminDecisionOption(
            value: decision,
            groupValue: selected,
            onChanged: controller.isSaving
                ? (_) {}
                : context.read<AdminReportsController>().setDecision,
          ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Response to reporter',
          hint: 'The reporter will see this.',
          controller: controller.responseController,
          maxLines: 4,
          error: responseError,
          onChanged: context.read<AdminReportsController>().setResponse,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${controller.response.trim().length}/$kAdminResponseMaxLength',
            style: AppTypography.caption,
          ),
        ),
        const SizedBox(height: 16),
        ThriftButton(
          label: selected == null
              ? 'Save decision'
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${reportDecisionLabel(selected)}?'),
        content: const Text(
          'The reporter will see this decision and your response. This does not ban the reported user or change payments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(reportDecisionCta(selected)),
          ),
        ],
      ),
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
