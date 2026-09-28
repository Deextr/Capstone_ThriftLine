import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../models/return_shipment.dart';
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
            ? const AdminDetailSkeleton()
            : dispute == null
            ? AdminErrorState(
                message:
                    controller.errorMessage ??
                    'Unable to load this delivery problem.',
                onRetry: () => context.read<AdminDisputesController>().load(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  AdminStatusChip(
                    status: dispute.status,
                    label: disputeStatusLabel(dispute.status),
                  ),
                  const SizedBox(height: 12),
                  Text(dispute.reason.label, style: AppTypography.heading),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted ${formatCompactDate(dispute.createdAt)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 28),
                  AdminDetailBlock(
                    label: 'People',
                    children: [
                      AdminPersonBlock(
                        embedded: true,
                        label: 'Buyer',
                        name: dispute.buyerDisplayName,
                        handle: adminHandle(
                          dispute.buyerUsername,
                          dispute.buyerDisplayName,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AdminPersonBlock(
                        embedded: true,
                        label: 'Seller',
                        name: dispute.sellerDisplayName,
                        handle: adminHandle(
                          dispute.sellerUsername,
                          dispute.sellerDisplayName,
                        ),
                        shopName: dispute.sellerShopName,
                      ),
                    ],
                  ),
                  AdminDetailBlock(
                    label: 'Problem',
                    children: [
                      Text(
                        dispute.details?.trim().isNotEmpty == true
                            ? dispute.details!.trim()
                            : 'No additional statement was provided.',
                        style: AppTypography.body,
                      ),
                    ],
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
                      label: 'Delivery',
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
                      label: 'Resolution',
                      children: [
                        Text(
                          dispute.adminNote?.trim().isNotEmpty == true
                              ? dispute.adminNote!.trim()
                              : 'This case is closed. No note was saved.',
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

    return AdminDecisionSection(
      title: 'Decision',
      children: [
        Text(
          'Closing records your review. Payment does not change.',
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
          'The case will be marked resolved. Payment does not change.',
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

class _PaymentResolution extends StatelessWidget {
  const _PaymentResolution({required this.controller});

  final AdminDisputesController controller;

  @override
  Widget build(BuildContext context) {
    final hold = controller.dispute?.paymentHold;
    if (hold == null) {
      return AdminDetailBlock(
        label: 'Payment',
        children: [
          Text(
            'No held payment was found for this order.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    return AdminDetailBlock(
      label: 'Payment',
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
          const SizedBox(height: 12),
          _ReturnOutcome(controller: controller),
        ],
        if (hold.canDecide) ...[
          const SizedBox(height: 8),
          _PaymentChoices(controller: controller, hold: hold),
        ],
      ],
    );
  }
}

enum _PaymentChoice { refund, release }

class _PaymentChoices extends StatefulWidget {
  const _PaymentChoices({required this.controller, required this.hold});

  final AdminDisputesController controller;
  final DeliveryPaymentHold hold;

  @override
  State<_PaymentChoices> createState() => _PaymentChoicesState();
}

class _PaymentChoicesState extends State<_PaymentChoices> {
  _PaymentChoice? _choice;

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    final saving = widget.controller.isSaving;
    final canSubmit = widget.controller.canSubmitPaymentDecision && !saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminChoiceRow(
          label: 'Refund the buyer',
          hint: refundBuyerCtaLabel(hold.amountCentavos),
          selected: _choice == _PaymentChoice.refund,
          onTap: saving
              ? () {}
              : () => setState(() => _choice = _PaymentChoice.refund),
        ),
        AdminChoiceRow(
          label: 'Release to the seller',
          hint: releaseSellerCtaLabel(hold.amountCentavos),
          selected: _choice == _PaymentChoice.release,
          onTap: saving
              ? () {}
              : () => setState(() => _choice = _PaymentChoice.release),
        ),
        if (_choice != null) ...[
          const SizedBox(height: 12),
          ThriftButton(
            label: _choice == _PaymentChoice.refund
                ? 'Refund buyer'
                : 'Release to seller',
            isLoading: saving,
            onPressed: !canSubmit
                ? null
                : _choice == _PaymentChoice.refund
                ? () => _confirmRefund(context, hold)
                : () => _confirmRelease(context, hold),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRefund(
    BuildContext context,
    DeliveryPaymentHold hold,
  ) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RefundChoiceDialog(
        amountLabel: refundBuyerCtaLabel(hold.amountCentavos),
      ),
    );
    if (choice == null || !context.mounted) return;
    final result = await context.read<AdminDisputesController>().refundPayment(
      returnRequired: choice,
    );
    if (!context.mounted) return;
    _showPaymentResult(context, result, refunded: true, returnRequired: choice);
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
            child: const Text('Release to seller'),
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
    bool returnRequired = false,
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
      final money = refundProviderMessage(result.refundProvider ?? 'internal');
      final item = returnRequired
          ? ' The seller must arrange the return. The refund does not wait for that.'
          : ' No return is needed.';
      showThriftSnackBar(context, '$money$item');
      return;
    }
    showThriftSnackBar(context, 'Amount released as seller earnings.');
  }
}

class _RefundChoiceDialog extends StatefulWidget {
  const _RefundChoiceDialog({required this.amountLabel});

  final String amountLabel;

  @override
  State<_RefundChoiceDialog> createState() => _RefundChoiceDialogState();
}

class _RefundChoiceDialogState extends State<_RefundChoiceDialog> {
  bool? _returnRequired;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.amountLabel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The buyer is refunded now. This amount will not become seller earnings. The refund does not wait for the seller.',
            ),
            const SizedBox(height: 16),
            Text('Physical item', style: AppTypography.subheading),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _returnRequired,
              onChanged: (value) => setState(() => _returnRequired = value),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: const Text('Return required'),
                    subtitle: const Text(
                      'The seller arranges and pays for pickup.',
                    ),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: const Text('No return needed'),
                    subtitle: const Text(
                      'The buyer keeps or discards the item.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep held'),
        ),
        TextButton(
          onPressed: _returnRequired == null
              ? null
              : () => Navigator.pop(context, _returnRequired),
          child: const Text('Refund buyer'),
        ),
      ],
    );
  }
}

class _ReturnOutcome extends StatelessWidget {
  const _ReturnOutcome({required this.controller});

  final AdminDisputesController controller;

  @override
  Widget build(BuildContext context) {
    final itemReturn = controller.dispute?.order?.itemReturn;
    if (itemReturn == null) {
      return _ReturnChoice(controller: controller);
    }

    final canStop = itemReturn.isOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          returnStatusLabel(itemReturn.status),
          style: AppTypography.subheading,
        ),
        const SizedBox(height: 4),
        Text(returnStatusHint(itemReturn.status), style: AppTypography.caption),
        if (canStop) ...[
          const SizedBox(height: 12),
          ThriftButton(
            label: 'Stop this return',
            variant: ThriftButtonVariant.outline,
            isLoading: controller.isSaving,
            onPressed: controller.isSaving ? null : () => _stop(context),
          ),
        ],
      ],
    );
  }

  Future<void> _stop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop this return?'),
        content: const Text(
          'The buyer stays refunded. The seller will not be asked to pick the item up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep return'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop this return'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await context.read<AdminDisputesController>().stopReturn();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Return stopped. The refund is unchanged.');
  }
}

class _ReturnChoice extends StatefulWidget {
  const _ReturnChoice({required this.controller});

  final AdminDisputesController controller;

  @override
  State<_ReturnChoice> createState() => _ReturnChoiceState();
}

class _ReturnChoiceState extends State<_ReturnChoice> {
  bool? _required;

  @override
  Widget build(BuildContext context) {
    final saving = widget.controller.isSaving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The refund is already recorded.', style: AppTypography.caption),
        const SizedBox(height: 4),
        AdminChoiceRow(
          label: 'Return required',
          hint: 'The seller arranges and pays for pickup.',
          selected: _required == true,
          onTap: saving ? () {} : () => setState(() => _required = true),
        ),
        AdminChoiceRow(
          label: 'No return needed',
          hint: 'The buyer keeps or discards the item.',
          selected: _required == false,
          onTap: saving ? () {} : () => setState(() => _required = false),
        ),
        if (_required != null) ...[
          const SizedBox(height: 8),
          ThriftButton(
            label: _required == true ? 'Require return' : 'No return needed',
            isLoading: saving,
            onPressed: saving ? null : () => _choose(context),
          ),
        ],
      ],
    );
  }

  Future<void> _choose(BuildContext context) async {
    final requiredReturn = _required;
    if (requiredReturn == null) return;
    final result = await context.read<AdminDisputesController>().refundPayment(
      returnRequired: requiredReturn,
    );
    if (!context.mounted) return;
    if (!result.success) {
      showThriftSnackBar(
        context,
        result.error ?? 'Could not save the return choice.',
        isError: true,
      );
      return;
    }
    showThriftSnackBar(
      context,
      requiredReturn
          ? 'Return required. The refund is unchanged.'
          : 'No return needed. The refund is unchanged.',
    );
  }
}
