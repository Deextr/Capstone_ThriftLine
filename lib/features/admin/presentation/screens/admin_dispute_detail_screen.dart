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
import '../../data/delivery_payment_hold.dart';
import '../../data/delivery_payment_resolve.dart';
import '../widgets/admin_review_widgets.dart';

class AdminDisputeDetailScreen extends StatelessWidget {
  const AdminDisputeDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDisputesController>();
    final dispute = controller.dispute;
    final order = dispute?.order;
    final shipment = dispute?.shipment;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Delivery problem'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(child: CircularProgressIndicator())
            : dispute == null
            ? AdminErrorState(
                message:
                    controller.errorMessage ?? 'Delivery problem not found.',
                onRetry: () => context.read<AdminDisputesController>().load(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  AdminStatusChip(
                    status: dispute.status,
                    label: disputeStatusLabel(dispute.status),
                  ),
                  const SizedBox(height: 12),
                  Text(dispute.reason.label, style: AppTypography.heading),
                  const SizedBox(height: 6),
                  Text(
                    formatCompactDate(dispute.createdAt),
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 28),
                  AdminDetailBlock(
                    label: 'Buyer statement',
                    children: [
                      Text(
                        dispute.details?.trim().isNotEmpty == true
                            ? dispute.details!.trim()
                            : 'No additional statement was provided.',
                        style: AppTypography.body,
                      ),
                    ],
                  ),
                  AdminPersonBlock(
                    label: 'Buyer',
                    name: dispute.buyerDisplayName,
                    handle: adminHandle(
                      dispute.buyerUsername,
                      dispute.buyerDisplayName,
                    ),
                    role: 'Buyer',
                  ),
                  AdminPersonBlock(
                    label: 'Seller',
                    name: dispute.sellerDisplayName,
                    handle: adminHandle(
                      dispute.sellerUsername,
                      dispute.sellerDisplayName,
                    ),
                    role: 'Seller',
                    shopName: dispute.sellerShopName,
                  ),
                  if (order != null || dispute.orderNumber != null)
                    AdminDetailBlock(
                      label: 'Order',
                      children: [
                        Text(
                          'Order #${order?.orderNumber ?? dispute.orderNumber}',
                          style: AppTypography.subheading,
                        ),
                        if ((order?.productTitle ?? dispute.orderTitle)
                                ?.isNotEmpty ==
                            true)
                          Text(
                            order?.productTitle ?? dispute.orderTitle!,
                            style: AppTypography.body,
                          ),
                        if (order != null)
                          Text(
                            '${orderStatusLabel(order.status)} · ${formatCompactDate(order.createdAt)}',
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  if (shipment != null)
                    AdminDetailBlock(
                      label: 'Shipment',
                      children: [
                        Text(
                          shipment.deliveryStatus.label,
                          style: AppTypography.subheading,
                        ),
                        if (shipment.hasRider)
                          Text(
                            [
                              if (shipment.riderName?.trim().isNotEmpty == true)
                                shipment.riderName!.trim(),
                              if (shipment.vehicleType?.trim().isNotEmpty ==
                                  true)
                                DeliveryVehicleType.fromDb(
                                  shipment.vehicleType,
                                ).label,
                              if (shipment.plateNumber?.trim().isNotEmpty ==
                                  true)
                                shipment.plateNumber!.trim(),
                            ].join(' · '),
                            style: AppTypography.body,
                          ),
                        if (shipment.deliveryNotes?.trim().isNotEmpty == true)
                          Text(
                            shipment.deliveryNotes!.trim(),
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  _PaymentResolution(controller: controller),
                  if (canCloseDispute(dispute.status))
                    _CloseForm(controller: controller)
                  else
                    AdminDetailBlock(
                      label: 'Admin resolution',
                      children: [
                        Text(
                          dispute.adminNote?.trim().isNotEmpty == true
                              ? dispute.adminNote!.trim()
                              : 'This delivery problem is resolved. No note was saved.',
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

class _CloseForm extends StatelessWidget {
  const _CloseForm({required this.controller});

  final AdminDisputesController controller;

  @override
  Widget build(BuildContext context) {
    final noteError = adminDisputeNoteError(controller.note);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionLabel('Admin resolution'),
        const SizedBox(height: 8),
        Text(
          'Closing this case records your review. It does not refund the buyer or release a payout.',
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
          variant: ThriftButtonVariant.outline,
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
          'The case will be marked resolved. Payment and payout state will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
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

class _PaymentResolution extends StatelessWidget {
  const _PaymentResolution({required this.controller});

  final AdminDisputesController controller;

  @override
  Widget build(BuildContext context) {
    final hold = controller.dispute?.paymentHold;
    if (hold == null) {
      return AdminDetailBlock(
        label: 'Payment resolution',
        children: [
          Text(
            'No held payment was found for this order.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return AdminDetailBlock(
      label: 'Payment resolution',
      children: [
        Text(
          deliveryHoldStatusLabel(hold.status),
          style: AppTypography.subheading,
        ),
        const SizedBox(height: 4),
        Text(formatCentavos(hold.amountCentavos), style: AppTypography.heading),
        const SizedBox(height: 4),
        Text(deliveryHoldHint(hold.status), style: AppTypography.caption),
        if (hold.isRefunded) ...[
          const SizedBox(height: 8),
          Text(
            refundProviderMessage(hold.refundProvider),
            style: AppTypography.body,
          ),
        ],
        if (hold.canDecide) ...[
          const SizedBox(height: 16),
          Text(
            'Choose what should happen to this payment.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ThriftButton(
            label: refundBuyerCtaLabel(hold.amountCentavos),
            color: AppColors.error,
            isLoading: controller.isSaving,
            onPressed: controller.canSubmitPaymentDecision
                ? () => _confirmRefund(context, hold)
                : null,
          ),
          const SizedBox(height: 8),
          ThriftButton(
            label: releaseSellerCtaLabel(hold.amountCentavos),
            isLoading: controller.isSaving,
            onPressed: controller.canSubmitPaymentDecision
                ? () => _confirmRelease(context, hold)
                : null,
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRefund(
    BuildContext context,
    DeliveryPaymentHold hold,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(refundBuyerCtaLabel(hold.amountCentavos)),
        content: const Text(
          'The buyer is refunded. This amount will not become seller earnings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep held'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(refundBuyerCtaLabel(hold.amountCentavos)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await context
        .read<AdminDisputesController>()
        .refundPayment();
    if (!context.mounted) return;
    _showPaymentResult(context, result, refunded: true);
  }

  Future<void> _confirmRelease(
    BuildContext context,
    DeliveryPaymentHold hold,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(releaseSellerCtaLabel(hold.amountCentavos)),
        content: const Text(
          'The held amount becomes available seller earnings. The buyer is not refunded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep held'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(releaseSellerCtaLabel(hold.amountCentavos)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await context
        .read<AdminDisputesController>()
        .releasePayment();
    if (!context.mounted) return;
    _showPaymentResult(context, result, refunded: false);
  }

  void _showPaymentResult(
    BuildContext context,
    DeliveryPaymentResult result, {
    required bool refunded,
  }) {
    if (!result.success) {
      showThriftSnackBar(
        context,
        result.error ?? 'Could not update this payment.',
        isError: true,
      );
      return;
    }
    if (refunded) {
      showThriftSnackBar(
        context,
        refundProviderMessage(result.refundProvider ?? 'internal'),
      );
      return;
    }
    showThriftSnackBar(context, 'Amount released as seller earnings.');
  }
}
