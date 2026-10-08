import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_order_report_timeline.dart';
import '../../data/admin_review_rules.dart';
import '../../data/delivery_payment_resolve.dart';
import 'admin_case_detail_widgets.dart';
import 'admin_dispute_review_modal_shell.dart';
import 'admin_order_report_detail_widgets.dart';
import 'order_dispute_financial_panel.dart';
import 'order_dispute_overview_section.dart';

Future<bool?> showOrderDisputeReviewModal({
  required BuildContext context,
  required String reportId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => ChangeNotifierProvider(
      create: (ctx) => AdminReportsController(
        supabase: ctx.read<SupabaseService>(),
        reportId: reportId,
      ),
      child: OrderDisputeReviewModal(reportId: reportId),
    ),
  );
}

class OrderDisputeReviewModal extends StatelessWidget {
  const OrderDisputeReviewModal({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final report = controller.report;

    return AdminDisputeReviewModalShell(
      title: 'Order Dispute Review',
      caseRef: report != null ? adminModerationCaseRef(report.id) : null,
      status: report?.status,
      isLoading: controller.isLoading,
      errorMessage: controller.errorMessage,
      onRetry: () => context.read<AdminReportsController>().load(),
      onClose: () => Navigator.of(context).pop(false),
      maxWidth: 920,
      body: report == null
          ? const SizedBox.shrink()
          : _OrderDisputeReviewBody(
              report: report,
              order: controller.relatedOrder,
              controller: controller,
            ),
      footer: Padding(
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

class _OrderDisputeReviewBody extends StatelessWidget {
  const _OrderDisputeReviewBody({
    required this.report,
    required this.order,
    required this.controller,
  });

  final CommunityReportModel report;
  final OrderModel? order;
  final AdminReportsController controller;

  @override
  Widget build(BuildContext context) {
    final parties = AdminOrderReportParties.from(report: report, order: order);
    final canDecide = canDecideReport(report.status);
    final hold = controller.paymentHold;
    final holdMissing =
        canDecide && (controller.relatedDispute == null || hold == null);
    final timeline = buildAdminOrderReportCaseTimeline(
      report: report,
      order: order,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrderDisputeOverviewSection(
            report: report,
            order: order,
            parties: parties,
          ),
          const SizedBox(height: 22),
          AdminDisputeModalSection(
            title: 'Report & evidence',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (report.details.trim().isNotEmpty) ...[
                  Text(
                    report.details.trim(),
                    style: AppTypography.body.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                ],
                AdminOrderReportEvidenceSection(
                  report: report,
                  reporterRoleLabel: parties.reporterRoleLabel,
                ),
              ],
            ),
          ),
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 22),
            AdminDisputeModalSection(
              title: 'Activity',
              child: AdminCaseTimeline(events: timeline),
            ),
          ],
          if (canDecide) ...[
            const SizedBox(height: 22),
            AdminDisputeModalSection(
              title: 'Admin decision',
              subtitle:
                  'Escrow stays on hold while you request evidence. Refund and release actions close the report.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hold != null) ...[
                    AdminOrderReportEscrowStrip(hold: hold),
                    const SizedBox(height: 14),
                  ],
                  if (holdMissing ||
                      hold == null ||
                      controller.relatedDispute == null)
                    AdminOrderReportMissingEscrowNotice(
                      disputeId: report.disputeId,
                    )
                  else
                    OrderDisputeFinancialPanel(
                      hold: hold,
                      isSaving: controller.isSaving,
                      canSubmitFinancial:
                          controller.canSubmitOrderFinancialResolution,
                      notesController: controller.responseController,
                      onNotesChanged: controller.setResponse,
                      notesError: controller.orderResolutionNotesError,
                      report: report,
                      order: order,
                      reporterPartyHint:
                          '${parties.reporterRoleLabel} — ${parties.reporterName}',
                      reportedPartyHint:
                          '${parties.reporterRoleLabel == 'Buyer' ? 'Seller' : 'Buyer'} — ${parties.reportedName}',
                      onConfirmRefund: (returnRequired) async {
                        final result = await controller
                            .confirmOrderFinancialResolution(
                              refundBuyer: true,
                              returnRequired: returnRequired,
                            );
                        if (!context.mounted) {
                          return const DeliveryPaymentResult(
                            success: false,
                            error: 'Context unavailable',
                          );
                        }
                        if (result.success) {
                          showThriftSnackBar(
                            context,
                            'Refund recorded and report closed.',
                          );
                          Navigator.of(context).pop(true);
                        } else if (result.error != null) {
                          showThriftSnackBar(
                            context,
                            result.error!,
                            isError: true,
                          );
                        }
                        return result;
                      },
                      onConfirmRelease: () async {
                        final result = await controller
                            .confirmOrderFinancialResolution(
                              refundBuyer: false,
                              returnRequired: null,
                            );
                        if (!context.mounted) {
                          return const DeliveryPaymentResult(
                            success: false,
                            error: 'Context unavailable',
                          );
                        }
                        if (result.success) {
                          showThriftSnackBar(
                            context,
                            'Payment released and report closed.',
                          );
                          Navigator.of(context).pop(true);
                        } else if (result.error != null) {
                          showThriftSnackBar(
                            context,
                            result.error!,
                            isError: true,
                          );
                        }
                        return result;
                      },
                      onRequestEvidence: (party, instruction) async {
                        final error = await controller
                            .submitOrderEvidenceRequest(
                              party: party,
                              instruction: instruction,
                            );
                        if (!context.mounted) return error;
                        if (error == null) {
                          showThriftSnackBar(
                            context,
                            'Evidence request sent. Escrow stays on hold.',
                          );
                        }
                        return error;
                      },
                    ),
                ],
              ),
            ),
          ] else if (report.adminResponse?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 22),
            AdminDisputeModalSection(
              title: 'Resolution',
              child: Text(
                report.adminResponse!.trim(),
                style: AppTypography.body.copyWith(height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
