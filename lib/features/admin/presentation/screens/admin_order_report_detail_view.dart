import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/order_model.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_order_report_timeline.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_case_detail_widgets.dart';
import '../widgets/admin_order_report_detail_widgets.dart';
import '../widgets/order_dispute_financial_panel.dart';

class AdminOrderReportDetailView extends StatelessWidget {
  const AdminOrderReportDetailView({
    super.key,
    required this.report,
    required this.order,
    required this.controller,
  });

  final CommunityReportModel report;
  final OrderModel? order;
  final AdminReportsController controller;

  @override
  Widget build(BuildContext context) {
    final canDecide = canDecideReport(report.status);
    final parties = AdminOrderReportParties.from(report: report, order: order);
    final hold = controller.paymentHold;
    final holdMissing =
        canDecide && (controller.relatedDispute == null || hold == null);

    void openOrder() {
      final id = order?.id ?? report.orderId;
      if (id != null && id.isNotEmpty) {
        context.push(RouteNames.adminOrderDetailFor(id));
      }
    }

    final timelineEvents = buildAdminOrderReportCaseTimeline(
      report: report,
      order: order,
    );

    return AdminCaseDetailPage(
      backLabel: 'Back to order reports',
      onBack: () => context.pop(),
      maxWidth: 960,
      child: AdminOrderReportMainColumn(
        report: report,
        order: order,
        parties: parties,
        timelineEvents: timelineEvents,
        canDecide: canDecide,
        holdMissing: holdMissing,
        hold: hold,
        onOpenOrder: (order != null || report.orderId?.isNotEmpty == true)
            ? openOrder
            : null,
        escrowId: hold?.escrowId,
        decisionSection: canDecide
            ? AdminOrderReportDecisionSection(
                holdMissing: holdMissing,
                disputeId: report.disputeId,
                hold: hold,
                panel: controller.relatedDispute != null && hold != null
                    ? OrderDisputeFinancialPanel(
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
                        onConfirmRefund: (returnRequired) =>
                            controller.confirmOrderFinancialResolution(
                              refundBuyer: true,
                              returnRequired: returnRequired,
                            ),
                        onConfirmRelease: () =>
                            controller.confirmOrderFinancialResolution(
                              refundBuyer: false,
                              returnRequired: null,
                            ),
                        onRequestEvidence: (party, instruction) =>
                            controller.submitOrderEvidenceRequest(
                              party: party,
                              instruction: instruction,
                            ),
                      )
                    : null,
              )
            : null,
      ),
    );
  }
}
