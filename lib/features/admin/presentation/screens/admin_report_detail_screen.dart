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
        title: const Text('Report details'),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AdminStatusChip(
                      status: report.status,
                      label: reportStatusLabel(report.status),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    reportReasonLabel(report.category),
                    style: AppTypography.heading,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${adminReportKindOf(category: report.category, orderId: report.orderId)} report · #${adminReportShortId(report.id)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 20),
                  AdminDetailBlock(
                    label: 'Report information',
                    children: [
                      AdminKeyValueRow(
                        label: 'Report ID',
                        value: '#${adminReportShortId(report.id)}',
                      ),
                      AdminKeyValueRow(
                        label: 'Type',
                        value: adminReportKindOf(
                          category: report.category,
                          orderId: report.orderId,
                        ),
                      ),
                      AdminKeyValueRow(
                        label: 'Reason',
                        value: reportReasonLabel(report.category),
                      ),
                      AdminKeyValueRow(
                        label: 'Submitted',
                        value: formatFullDate(report.createdAt),
                      ),
                      AdminKeyValueRow(
                        label: 'Status',
                        value: reportStatusLabel(report.status),
                      ),
                    ],
                  ),
                  AdminDetailBlock(
                    label: 'People involved',
                    children: [
                      AdminPersonBlock(
                        embedded: true,
                        label: 'Reporter',
                        name: report.reporterDisplayName,
                        handle: adminHandle(
                          report.reporterUsername,
                          report.reporterDisplayName,
                        ),
                        role: accountRoleLabel(report.reporterRole),
                      ),
                      const SizedBox(height: 16),
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
                    ],
                  ),
                  if (report.orderId != null)
                    AdminDetailBlock(
                      label: 'Order information',
                      children: [
                        AdminKeyValueRow(
                          label: 'Order',
                          value: order != null
                              ? '#${order.orderNumber}'
                              : report.orderNumber == null
                              ? 'Related order'
                              : '#${report.orderNumber}',
                        ),
                        if ((order?.productTitle ?? report.orderTitle)
                                ?.isNotEmpty ==
                            true)
                          AdminKeyValueRow(
                            label: 'Item',
                            value: order?.productTitle ?? report.orderTitle!,
                          ),
                        if (order != null)
                          AdminKeyValueRow(
                            label: 'Order status',
                            value:
                                '${orderStatusLabel(order.status)} · ${formatFullDate(order.createdAt)}',
                          ),
                        if (order != null)
                          AdminKeyValueRow(
                            label: 'Amount',
                            value: formatCurrency(order.total),
                          ),
                      ],
                    ),
                  AdminDetailBlock(
                    label: 'Description',
                    children: [Text(report.details, style: AppTypography.body)],
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
                      label: 'Admin action / Resolution',
                      children: [
                        AdminKeyValueRow(
                          label: 'Decision',
                          value: reportStatusLabel(report.status),
                        ),
                        if (report.resolvedAt != null)
                          AdminKeyValueRow(
                            label: 'Resolved',
                            value: formatFullDate(report.resolvedAt!),
                          ),
                        const SizedBox(height: 4),
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
      title: 'Admin action / Resolution',
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
