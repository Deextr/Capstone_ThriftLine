import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_disputes_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_delivery_dispute.dart';
import '../widgets/admin_case_detail_widgets.dart';
import '../widgets/admin_escrow_decision_panel.dart';
import '../widgets/admin_review_widgets.dart';

class AdminDisputeDetailScreen extends StatelessWidget {
  const AdminDisputeDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesController>();
    final dispute = controller.dispute;

    if (controller.isLoading) {
      return ColoredBox(
        color: AppColors.background,
        child: SafeArea(child: const AdminDetailSkeleton()),
      );
    }

    if (dispute == null) {
      return AdminCaseDetailPage(
        backLabel: 'Back to disputes',
        onBack: () => context.pop(),
        child: AdminErrorState(
          message:
              controller.errorMessage ??
              'Unable to load this delivery problem.',
          onRetry: () => context.read<AdminDisputesController>().load(),
        ),
      );
    }

    final order = dispute.order;
    final shipment = dispute.shipment;

    return AdminCaseDetailPage(
      backLabel: 'Back to disputes',
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminCaseDetailHeader(
            typeLabel: 'Delivery',
            title:
                '${dispute.reason.label} ${adminModerationCaseRef(dispute.id)}',
            status: dispute.status,
            statusLabel: disputeStatusLabel(dispute.status),
            submittedAt: dispute.createdAt,
          ),
          AdminCaseDetailSection(
            first: true,
            title: 'Case overview',
            children: [
              AdminCaseDetailField(
                label: 'Reason',
                value: dispute.reason.label,
              ),
              AdminCaseDetailField(
                label: 'Statement',
                value: dispute.details?.trim().isNotEmpty == true
                    ? dispute.details!.trim()
                    : 'No additional statement was provided.',
                multiline: true,
              ),
              AdminCaseDetailField(
                label: 'Status',
                value: disputeStatusLabel(dispute.status),
              ),
            ],
          ),
          if (order != null || dispute.orderNumber != null)
            AdminCaseDetailSection(
              title: 'Related order',
              children: [
                AdminCaseDetailField(
                  label: 'Order',
                  value: '#${order?.orderNumber ?? dispute.orderNumber}',
                ),
                if ((order?.productTitle ?? dispute.orderTitle)?.isNotEmpty ==
                    true)
                  AdminCaseDetailField(
                    label: 'Product',
                    value: order?.productTitle ?? dispute.orderTitle!,
                  ),
                if (order != null) ...[
                  AdminCaseDetailField(
                    label: 'Order status',
                    value: orderStatusLabel(order.status),
                  ),
                  AdminCaseDetailField(
                    label: 'Amount',
                    value: formatCurrency(order.total),
                  ),
                  AdminCaseDetailField(
                    label: 'Placed',
                    value: formatAdminTableDateTime(order.createdAt),
                  ),
                ],
              ],
            ),
          AdminCaseDetailSection(
            title: 'Parties involved',
            children: [
              AdminCasePartiesRow(
                leftTitle: 'Buyer',
                leftName: dispute.buyerDisplayName,
                leftLines: [
                  adminHandle(dispute.buyerUsername, dispute.buyerDisplayName),
                ],
                rightTitle: 'Seller',
                rightName: dispute.sellerDisplayName,
                rightLines: [
                  adminHandle(
                    dispute.sellerUsername,
                    dispute.sellerDisplayName,
                  ),
                  if (dispute.sellerShopName?.trim().isNotEmpty == true)
                    dispute.sellerShopName!.trim(),
                ],
              ),
            ],
          ),
          if (shipment != null)
            AdminCaseDetailSection(
              title: 'Delivery',
              children: [
                AdminCaseDetailField(
                  label: 'Status',
                  value: shipment.deliveryStatus.label,
                ),
                if (shipment.hasRider)
                  AdminCaseDetailField(
                    label: 'Rider',
                    value: [
                      if (shipment.riderName?.trim().isNotEmpty == true)
                        shipment.riderName!.trim(),
                      if (shipment.vehicleType?.trim().isNotEmpty == true)
                        DeliveryVehicleType.fromDb(shipment.vehicleType).label,
                      if (shipment.plateNumber?.trim().isNotEmpty == true)
                        shipment.plateNumber!.trim(),
                    ].join(' · '),
                  ),
                if (shipment.deliveryNotes?.trim().isNotEmpty == true)
                  AdminCaseDetailField(
                    label: 'Notes',
                    value: shipment.deliveryNotes!.trim(),
                    multiline: true,
                  ),
              ],
            ),
          AdminCaseDetailSection(
            title: 'Payment & escrow',
            children: [
              AdminEscrowDecisionPanel(
                hold: controller.dispute?.paymentHold,
                itemReturn: controller.dispute?.order?.itemReturn,
                isSaving: controller.isSaving,
                canSubmit: controller.canSubmitPaymentDecision,
                onRelease: () =>
                    context.read<AdminDisputesController>().releasePayment(),
                onRefund: (returnRequired) => context
                    .read<AdminDisputesController>()
                    .refundPayment(returnRequired: returnRequired),
                onStopReturn: () =>
                    context.read<AdminDisputesController>().stopReturn(),
              ),
            ],
          ),
          AdminCaseDetailSection(
            title: 'Case activity',
            children: [AdminCaseTimeline(events: _disputeTimeline(dispute))],
          ),
          if (canCloseDispute(dispute.status))
            AdminCaseDecisionPanel(
              title: 'Admin decision',
              lead:
                  'Review delivery and payment details before closing the case or updating held funds.',
              children: [_CloseForm(controller: controller)],
            )
          else
            AdminCaseDetailSection(
              title: 'Resolution',
              children: [
                AdminCaseDetailBodyText(
                  text: dispute.adminNote?.trim().isNotEmpty == true
                      ? dispute.adminNote!.trim()
                      : 'This case is closed. No note was saved.',
                ),
                if (dispute.resolvedAt != null)
                  AdminCaseDetailField(
                    label: 'Closed',
                    value: formatAdminTableDateTime(dispute.resolvedAt!),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static List<AdminCaseTimelineEvent> _disputeTimeline(
    AdminDeliveryDispute dispute,
  ) {
    final events = <AdminCaseTimelineEvent>[
      AdminCaseTimelineEvent(title: 'Dispute submitted', at: dispute.createdAt),
    ];
    if (canCloseDispute(dispute.status)) {
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
          title: disputeStatusLabel(dispute.status),
          at: dispute.resolvedAt,
        ),
      );
    }
    return events;
  }
}

class _CloseForm extends StatelessWidget {
  const _CloseForm({required this.controller});

  final AdminDisputesController controller;

  @override
  Widget build(BuildContext context) {
    final noteError = adminDisputeNoteError(controller.note);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dismiss the buyer\'s claim. The payment hold from this dispute is '
          'removed and seller earnings update when the order is eligible.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Note (optional)',
          hint: 'Add a short internal note if needed.',
          controller: controller.noteController,
          maxLines: 4,
          error: controller.note.trim().isEmpty ? null : noteError,
          onChanged: context.read<AdminDisputesController>().setNote,
        ),
        const SizedBox(height: 16),
        ThriftButton(
          label: 'Close case',
          isLoading: controller.isSaving,
          onPressed: controller.canSubmitClose ? () => _confirm(context) : null,
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this delivery problem?'),
        content: const Text(
          'The case will be marked resolved and the dispute hold on payment '
          'will be cleared. Use “Release to seller” below if you need to '
          'release earnings immediately while the order is still open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep open'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close case'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final error = await context.read<AdminDisputesController>().closeCase();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Delivery problem closed.');
  }
}
