import 'package:flutter/material.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/return_shipment.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/delivery_payment_hold.dart';
import '../../data/delivery_payment_resolve.dart';
import '../widgets/admin_case_detail_widgets.dart';
import '../widgets/admin_review_widgets.dart';

/// Shared admin UI for escrow refund vs release (order reports & delivery disputes).
class AdminEscrowDecisionPanel extends StatelessWidget {
  const AdminEscrowDecisionPanel({
    super.key,
    required this.hold,
    this.itemReturn,
    required this.isSaving,
    required this.canSubmit,
    required this.onRelease,
    required this.onRefund,
    this.onStopReturn,
    this.showHoldSummary = true,
  });

  final DeliveryPaymentHold? hold;
  final ReturnShipment? itemReturn;
  final bool isSaving;
  final bool canSubmit;
  final Future<DeliveryPaymentResult> Function() onRelease;
  final Future<DeliveryPaymentResult> Function(bool returnRequired) onRefund;
  final Future<String?> Function()? onStopReturn;
  final bool showHoldSummary;

  @override
  Widget build(BuildContext context) {
    final paymentHold = hold;
    if (paymentHold == null) {
      return AdminCaseDetailBodyText(
        text: 'No held payment was found for this order.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHoldSummary) ...[
          AdminCaseDetailField(
            label: 'Hold status',
            value: deliveryHoldStatusLabel(paymentHold.status),
          ),
          AdminCaseDetailField(
            label: 'Amount',
            value: formatCentavos(paymentHold.amountCentavos),
          ),
          AdminCaseDetailField(
            label: 'Details',
            value: deliveryHoldHint(paymentHold.status),
            multiline: true,
          ),
        ],
        if (paymentHold.isRefunded) ...[
          AdminCaseDetailField(
            label: 'Refund',
            value: refundProviderMessage(paymentHold.refundProvider),
            multiline: true,
          ),
          const SizedBox(height: 8),
          _ReturnOutcomeSection(
            itemReturn: itemReturn,
            isSaving: isSaving,
            onRefund: onRefund,
            onStopReturn: onStopReturn,
          ),
        ],
        if (paymentHold.canDecide) ...[
          const SizedBox(height: 12),
          _FinancialResolutionChoices(
            hold: paymentHold,
            isSaving: isSaving,
            canSubmit: canSubmit,
            onRelease: onRelease,
            onRefund: onRefund,
          ),
        ],
      ],
    );
  }
}

enum _FinancialChoice { refund, release }

class _FinancialResolutionChoices extends StatefulWidget {
  const _FinancialResolutionChoices({
    required this.hold,
    required this.isSaving,
    required this.canSubmit,
    required this.onRelease,
    required this.onRefund,
  });

  final DeliveryPaymentHold hold;
  final bool isSaving;
  final bool canSubmit;
  final Future<DeliveryPaymentResult> Function() onRelease;
  final Future<DeliveryPaymentResult> Function(bool returnRequired) onRefund;

  @override
  State<_FinancialResolutionChoices> createState() =>
      _FinancialResolutionChoicesState();
}

class _FinancialResolutionChoicesState
    extends State<_FinancialResolutionChoices> {
  _FinancialChoice? _financial;
  bool? _returnRequired;

  @override
  Widget build(BuildContext context) {
    final saving = widget.isSaving;
    final canSubmit = widget.canSubmit && !saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Financial resolution', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text(
          'Who should receive the held funds?',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 8),
        AdminChoiceRow(
          label: 'Refund buyer',
          hint: refundBuyerCtaLabel(widget.hold.amountCentavos),
          selected: _financial == _FinancialChoice.refund,
          onTap: saving
              ? () {}
              : () => setState(() {
                  _financial = _FinancialChoice.refund;
                  _returnRequired = null;
                }),
        ),
        AdminChoiceRow(
          label: 'Release payment to seller',
          hint: releaseSellerCtaLabel(widget.hold.amountCentavos),
          selected: _financial == _FinancialChoice.release,
          onTap: saving
              ? () {}
              : () => setState(() {
                  _financial = _FinancialChoice.release;
                  _returnRequired = null;
                }),
        ),
        if (_financial == _FinancialChoice.refund) ...[
          const SizedBox(height: 16),
          Text(
            'What should happen to the item?',
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 4),
          Text(
            'Return responsibility: the seller arranges the return pickup.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 8),
          AdminChoiceRow(
            label: 'Return item to seller',
            hint: 'Seller arranges pickup after refund is recorded.',
            selected: _returnRequired == true,
            onTap: saving
                ? () {}
                : () => setState(() => _returnRequired = true),
          ),
          AdminChoiceRow(
            label: 'No return required',
            hint: 'Example: empty package or missing item.',
            selected: _returnRequired == false,
            onTap: saving
                ? () {}
                : () => setState(() => _returnRequired = false),
          ),
        ],
        if (_financial != null &&
            (_financial == _FinancialChoice.release ||
                _returnRequired != null)) ...[
          const SizedBox(height: 16),
          ThriftButton(
            label: _financial == _FinancialChoice.release
                ? 'Release to seller'
                : 'Refund buyer',
            isLoading: saving,
            onPressed: !canSubmit
                ? null
                : _financial == _FinancialChoice.release
                ? () => _confirmRelease(context)
                : () => _confirmRefund(context),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRefund(BuildContext context) async {
    final returnRequired = _returnRequired;
    if (returnRequired == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm buyer refund?'),
        content: Text(
          returnRequired
              ? 'This resolves the dispute in the buyer\'s favor. The buyer is refunded now. '
                    'The item must be returned and the seller will arrange pickup.'
              : 'This resolves the dispute in the buyer\'s favor and refunds the buyer. '
                    'No item return is required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Refund buyer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await widget.onRefund(returnRequired);
    if (!context.mounted) return;
    _showResult(
      context,
      result,
      refunded: true,
      returnRequired: returnRequired,
    );
  }

  Future<void> _confirmRelease(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(releaseSellerCtaLabel(widget.hold.amountCentavos)),
        content: const Text(
          'This resolves the dispute in the seller\'s favor. The held payment is '
          'released as seller earnings. The buyer is not refunded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Release to seller'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await widget.onRelease();
    if (!context.mounted) return;
    _showResult(context, result, refunded: false);
  }

  void _showResult(
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
          ? ' The seller must arrange the return.'
          : ' No return is required.';
      showThriftSnackBar(context, '$money$item');
      return;
    }
    showThriftSnackBar(context, 'Payment released to the seller.');
  }
}

class _ReturnOutcomeSection extends StatefulWidget {
  const _ReturnOutcomeSection({
    required this.itemReturn,
    required this.isSaving,
    required this.onRefund,
    this.onStopReturn,
  });

  final ReturnShipment? itemReturn;
  final bool isSaving;
  final Future<DeliveryPaymentResult> Function(bool returnRequired) onRefund;
  final Future<String?> Function()? onStopReturn;

  @override
  State<_ReturnOutcomeSection> createState() => _ReturnOutcomeSectionState();
}

class _ReturnOutcomeSectionState extends State<_ReturnOutcomeSection> {
  bool? _required;

  @override
  Widget build(BuildContext context) {
    final itemReturn = widget.itemReturn;
    if (itemReturn != null) {
      final canStop = itemReturn.isOpen && widget.onStopReturn != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            returnStatusLabel(itemReturn.status),
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 4),
          Text(
            returnStatusHint(itemReturn.status),
            style: AppTypography.caption,
          ),
          if (canStop) ...[
            const SizedBox(height: 12),
            ThriftButton(
              label: 'Stop this return',
              variant: ThriftButtonVariant.outline,
              isLoading: widget.isSaving,
              onPressed: widget.isSaving ? null : () => _stopReturn(context),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Return choice not recorded yet.', style: AppTypography.caption),
        const SizedBox(height: 8),
        AdminChoiceRow(
          label: 'Return required',
          hint: 'The seller arranges and pays for pickup.',
          selected: _required == true,
          onTap: widget.isSaving
              ? () {}
              : () => setState(() => _required = true),
        ),
        AdminChoiceRow(
          label: 'No return needed',
          hint: 'The buyer keeps or discards the item.',
          selected: _required == false,
          onTap: widget.isSaving
              ? () {}
              : () => setState(() => _required = false),
        ),
        if (_required != null) ...[
          const SizedBox(height: 8),
          ThriftButton(
            label: _required == true ? 'Require return' : 'No return needed',
            isLoading: widget.isSaving,
            onPressed: widget.isSaving
                ? null
                : () => _saveReturnChoice(context),
          ),
        ],
      ],
    );
  }

  Future<void> _saveReturnChoice(BuildContext context) async {
    final requiredReturn = _required;
    if (requiredReturn == null) return;
    final result = await widget.onRefund(requiredReturn);
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
          ? 'Return required recorded.'
          : 'No return required recorded.',
    );
  }

  Future<void> _stopReturn(BuildContext context) async {
    final stop = widget.onStopReturn;
    if (stop == null) return;
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
            child: const Text('Stop return'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await stop();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Return stopped.');
  }
}
