import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_refund_controller.dart';
import '../../data/delivery_payment_hold.dart';
import '../../domain/admin_refund.dart';
import 'admin_ui_components.dart';

/// Refund status and follow-up actions for a refunded escrow.
class AdminRefundPanel extends StatelessWidget {
  const AdminRefundPanel({
    super.key,
    required this.hold,
    this.onChanged,
    this.forDetailDialog = false,
  });

  final DeliveryPaymentHold hold;
  final VoidCallback? onChanged;

  /// Omits summary rows shown in [AdminBuyerRefundDetailDialog].
  final bool forDetailDialog;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AdminRefundController(
        supabase: context.read<SupabaseService>(),
        hold: hold,
        onRefundChanged: onChanged,
      ),
      child: _RefundPanelBody(forDetailDialog: forDetailDialog),
    );
  }
}

class _RefundPanelBody extends StatelessWidget {
  const _RefundPanelBody({required this.forDetailDialog});

  final bool forDetailDialog;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminRefundController>();
    final hold = controller.hold;
    final details = controller.details;
    final state = hold.refundState;

    final hint = adminRefundStateHint(hold);
    final showProviderBlock =
        hold.paymongoRefundId != null ||
        hold.refundProviderStatus != null ||
        (hold.refundProviderError != null && !hold.refundIsComplete) ||
        hold.refundLastCheckedAt != null ||
        (state == 'awaiting_buyer_claim' && details != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!forDetailDialog) ...[
          Row(
            children: [
              AdminStatusBadge(
                status: _badgeKey(state),
                label: adminRefundStateLabel(state),
              ),
              if (controller.isLoading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (hint.isNotEmpty)
            Text(
              hint,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          const SizedBox(height: 10),
          _Row(
            label: 'Refund amount',
            value: formatCentavos(hold.amountCentavos),
          ),
        ] else ...[
          if (controller.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (hint.isNotEmpty && !hold.refundIsComplete)
            _HintBanner(message: hint),
        ],
        if (showProviderBlock) ...[
          SizedBox(height: forDetailDialog ? 14 : 10),
          _PanelSubheading(
            title: forDetailDialog ? 'Payment provider' : 'PayMongo',
          ),
          if (hold.paymongoRefundId != null)
            _Row(label: 'Refund ID', value: hold.paymongoRefundId!),
          if (hold.refundProviderStatus != null)
            _Row(label: 'Status', value: hold.refundProviderStatus!),
          if (hold.refundProviderError != null && !hold.refundIsComplete)
            _Row(label: 'Last error', value: hold.refundProviderError!),
          if (hold.refundLastCheckedAt != null)
            _Row(
              label: 'Last checked',
              value: formatAdminTableDateTime(hold.refundLastCheckedAt!),
            ),
          if (!forDetailDialog && hold.refundCompletedAt != null)
            _Row(
              label: 'Completed',
              value: formatAdminTableDateTime(hold.refundCompletedAt!),
            ),
          if (state == 'awaiting_buyer_claim' && details != null)
            _Row(
              label: 'Claim link',
              value: details.transferLinkExpiresAt == null
                  ? (details.hasTransferLink ? 'Sent to buyer' : 'Not provided')
                  : 'Expires ${formatAdminTableDateTime(details.transferLinkExpiresAt!)}',
            ),
        ] else if (!forDetailDialog && hold.refundCompletedAt != null)
          _Row(
            label: 'Completed',
            value: formatAdminTableDateTime(hold.refundCompletedAt!),
          ),
        if (controller.loadError != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.loadError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        if (details != null && details.hasManualRecord) ...[
          const SizedBox(height: 14),
          _ManualRecord(details: details, compact: forDetailDialog),
        ] else if (state == 'manual_required') ...[
          const SizedBox(height: 14),
          _BuyerGcash(details: details),
        ],
        if (controller.actionMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            controller.actionMessage!,
            style: AppTypography.caption.copyWith(color: AppColors.primary),
          ),
        ],
        if (controller.actionError != null && !controller.showManualForm) ...[
          const SizedBox(height: 10),
          Text(
            controller.actionError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        if (controller.showManualForm)
          _ManualRefundForm(compact: forDetailDialog)
        else
          _ProviderActions(compact: forDetailDialog),
        if (!forDetailDialog && controller.attempts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PanelSubheading(title: 'PayMongo activity'),
          const SizedBox(height: 6),
          for (final attempt in controller.attempts.take(8))
            _AttemptRow(attempt: attempt),
        ],
      ],
    );
  }

  String _badgeKey(String? state) => switch (state) {
    'succeeded' || 'manual_completed' => 'completed',
    'manual_required' => 'failed',
    'awaiting_buyer_claim' => 'pending',
    _ => 'processing',
  };
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSubheading extends StatelessWidget {
  const _PanelSubheading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.label.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _ProviderActions extends StatelessWidget {
  const _ProviderActions({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminRefundController>();
    final busy = controller.busyAction;
    final buttons = <Widget>[
      if (controller.canCheckProvider)
        OutlinedButton.icon(
          onPressed: busy != null ? null : controller.checkProvider,
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: Text(
            busy == AdminRefundAction.check
                ? 'Checking PayMongo…'
                : 'Check PayMongo status',
          ),
        ),
      if (controller.canRetryProvider)
        OutlinedButton.icon(
          onPressed: busy != null ? null : () => _confirmRetry(context),
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: Text(
            busy == AdminRefundAction.retry
                ? 'Asking PayMongo…'
                : 'Retry PayMongo refund',
          ),
        ),
      if (controller.canRecordManual)
        FilledButton(
          onPressed: busy != null
              ? null
              : () => controller.toggleManualForm(true),
          child: const Text('Record manual GCash refund'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    final actions = Wrap(spacing: 8, runSpacing: 8, children: buttons);
    if (!compact) {
      return Padding(padding: const EdgeInsets.only(top: 12), child: actions);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Admin actions',
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              actions,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRetry(BuildContext context) async {
    final controller = context.read<AdminRefundController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retry the PayMongo refund?'),
        content: Text(
          'ThriftLine first checks PayMongo for an existing refund, then asks '
          'PayMongo to return ${formatCentavos(controller.hold.amountCentavos)}. '
          'Do not send GCash by hand while this runs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retry refund'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.retryProvider();
  }
}

class _BuyerGcash extends StatelessWidget {
  const _BuyerGcash({required this.details});

  final AdminRefundDetails? details;

  @override
  Widget build(BuildContext context) {
    final d = details;
    if (d == null || !d.buyerSentGcash) {
      return Text(
        'The buyer has not sent GCash details yet. They are asked for them in '
        'their transaction history.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buyer GCash',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d.gcashAccountName!,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SelectableText(
                  formatPhMobile(d.gcashMobileNumber),
                  style: AppTypography.body,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy number',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: d.gcashMobileNumber ?? ''));
              showThriftSnackBar(context, 'GCash number copied.');
            },
          ),
        ],
      ),
    );
  }
}

class _ManualRecord extends StatelessWidget {
  const _ManualRecord({required this.details, this.compact = false});

  final AdminRefundDetails details;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final evidence = details.manualEvidencePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelSubheading(
          title: compact ? 'GCash transfer record' : 'Manual GCash transfer',
        ),
        const SizedBox(height: 8),
        if (details.manualAmountCentavos != null)
          _Row(
            label: 'Amount sent',
            value: formatCentavos(details.manualAmountCentavos!),
          ),
        _Row(label: 'GCash reference', value: details.manualReference ?? '—'),
        if (details.gcashAccountName != null)
          _Row(
            label: 'Sent to',
            value:
                '${details.gcashAccountName} · '
                '${formatPhMobile(details.gcashMobileNumber)}',
          ),
        if (details.manualSentAt != null)
          _Row(
            label: 'Sent on',
            value: formatAdminTableDateTime(details.manualSentAt!),
          ),
        if (details.manualNote != null)
          _Row(label: 'Note', value: details.manualNote!),
        if (evidence != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View receipt'),
              onPressed: () async {
                final opened = await context
                    .read<AdminRefundController>()
                    .openEvidence(evidence);
                if (!opened && context.mounted) {
                  showThriftSnackBar(
                    context,
                    'We could not open the receipt.',
                    isError: true,
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

class _ManualRefundForm extends StatefulWidget {
  const _ManualRefundForm({this.compact = false});

  final bool compact;

  @override
  State<_ManualRefundForm> createState() => _ManualRefundFormState();
}

class _ManualRefundFormState extends State<_ManualRefundForm> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _note = TextEditingController();
  DateTime? _sentAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final details = context.read<AdminRefundController>().details;
    _name.text = details?.gcashAccountName ?? '';
    _mobile.text = details?.gcashMobileNumber ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _name.dispose();
    _mobile.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _sentAt ?? now,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
    );
    if (picked == null) return;
    final time = TimeOfDay.fromDateTime(_sentAt ?? now);
    setState(() {
      final candidate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
      _sentAt = candidate.isAfter(now) ? now : candidate;
    });
  }

  Future<void> _submit() async {
    final ok = await context.read<AdminRefundController>().recordManualRefund(
      amountText: _amount.text,
      reference: _reference.text,
      sentAt: _sentAt,
      accountName: _name.text,
      mobileNumber: _mobile.text,
      note: _note.text,
    );
    if (ok && mounted) {
      showThriftSnackBar(context, 'Manual GCash refund recorded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminRefundController>();
    final errors = controller.fieldErrors;
    final evidence = controller.evidence;
    final busy = controller.isBusy;
    final amount = controller.hold.amountCentavos;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Record GCash refund',
            style: widget.compact
                ? AppTypography.label.copyWith(fontWeight: FontWeight.w700)
                : AppTypography.subheading,
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 4),
            Text(
              'Send ${formatCentavos(amount)} from the ThriftLine GCash account, '
              'then enter the receipt details.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Buyer GCash name',
            controller: _name,
            error: errors['name'],
            readOnly: busy,
            maxLength: 80,
          ),
          const SizedBox(height: 10),
          ThriftTextField(
            label: 'Buyer GCash number',
            hint: '09XXXXXXXXX',
            controller: _mobile,
            error: errors['mobile'],
            readOnly: busy,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
            ],
          ),
          const SizedBox(height: 10),
          ThriftTextField(
            label: 'Amount sent (PHP)',
            hint: (amount / 100).toStringAsFixed(2),
            controller: _amount,
            error: errors['amount'],
            readOnly: busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
          ),
          const SizedBox(height: 10),
          ThriftTextField(
            label: 'GCash reference number',
            controller: _reference,
            error: errors['reference'],
            readOnly: busy,
            maxLength: 64,
          ),
          const SizedBox(height: 10),
          Text('Date sent', style: AppTypography.label),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                _sentAt == null ? 'Choose date' : formatFullDate(_sentAt!),
              ),
            ),
          ),
          if (errors['date'] != null) ...[
            const SizedBox(height: 4),
            Text(
              errors['date']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 12),
          Text('GCash receipt', style: AppTypography.label),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : controller.pickEvidence,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(evidence == null ? 'Attach receipt' : 'Replace'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  evidence?.fileName ?? 'Screenshot of the sent transfer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: evidence == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (errors['evidence'] != null) ...[
            const SizedBox(height: 4),
            Text(
              errors['evidence']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 10),
          ThriftTextField(
            label: 'Note (optional)',
            controller: _note,
            readOnly: busy,
            maxLines: 2,
            maxLength: 1000,
          ),
          if (controller.actionError != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.actionError!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => controller.toggleManualForm(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(
                  controller.busyAction == AdminRefundAction.manual
                      ? 'Saving…'
                      : 'Save refund record',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt});

  final AdminRefundAttempt attempt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attempt.title, style: AppTypography.tableBody),
          Text(
            [
              formatAdminTableDateTime(attempt.createdAt),
              if (attempt.detail.isNotEmpty) attempt.detail,
            ].join(' · '),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: AppTypography.tableBody),
          ),
        ],
      ),
    );
  }
}
