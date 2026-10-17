import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/admin_seller_payouts_controller.dart';
import '../../data/seller_payout_rejection_reasons.dart';
import '../../domain/admin_seller_payout.dart';
import 'admin_report_decision_widgets.dart';
import 'admin_ui_components.dart';

enum _DialogMode { view, reject }

class AdminSellerPayoutDetailDialog extends StatefulWidget {
  const AdminSellerPayoutDetailDialog({super.key, required this.payoutId});

  final String payoutId;

  @override
  State<AdminSellerPayoutDetailDialog> createState() =>
      _AdminSellerPayoutDetailDialogState();
}

class _AdminSellerPayoutDetailDialogState
    extends State<AdminSellerPayoutDetailDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _otherRejectDetail = TextEditingController();
  DateTime? _sentAt = DateTime.now();
  _DialogMode _mode = _DialogMode.view;
  String? _rejectReasonId;
  bool _rejectAttempted = false;
  AdminSellerPayout? _lastKnown;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    _otherRejectDetail.dispose();
    super.dispose();
  }

  AdminSellerPayout? _find(AdminSellerPayoutsController controller) {
    for (final p in controller.rows) {
      if (p.payoutId == widget.payoutId) return p;
    }
    return null;
  }

  String? _resolvedRejectReason() {
    return sellerPayoutRejectionReasonMessage(
      reasonId: _rejectReasonId,
      otherDetail: _otherRejectDetail.text,
    );
  }

  Future<void> _pickDate(AdminSellerPayout payout) async {
    final now = DateTime.now();
    final first = (payout.requestedAt ?? now).subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _sentAt ?? now,
      firstDate: first,
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

  Future<void> _record(AdminSellerPayout payout) async {
    final ok = await context
        .read<AdminSellerPayoutsController>()
        .recordTransfer(
          payout: payout,
          amountText: _amount.text,
          reference: _reference.text,
          sentAt: _sentAt,
          note: _note.text,
        );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
    showThriftSnackBar(
      context,
      'Transfer recorded. The seller can now see the GCash reference.',
    );
  }

  Future<void> _reject(AdminSellerPayout payout) async {
    final selectionError = validatePayoutRejectionSelection(
      reasonId: _rejectReasonId,
      otherDetail: _otherRejectDetail.text,
    );
    if (selectionError != null) {
      setState(() => _rejectAttempted = true);
      return;
    }
    final reason = _resolvedRejectReason()!;
    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Reject this payout?',
      rows: [
        ('Seller', payout.sellerDisplayName),
        ('Amount', formatCentavos(payout.amountCentavos)),
      ],
      messagePreview: reason,
      detailText:
          'The seller will see this reason. The amount returns to their available earnings.',
      confirmLabel: 'Reject payout',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final ok = await context.read<AdminSellerPayoutsController>().reject(
      payout: payout,
      reason: reason,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
    showThriftSnackBar(
      context,
      'Payout rejected. The amount is back in the seller\'s balance.',
    );
  }

  void _enterRejectMode() {
    setState(() {
      _mode = _DialogMode.reject;
      _rejectReasonId = null;
      _rejectAttempted = false;
      _otherRejectDetail.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminSellerPayoutsController>();
    final payout = _find(controller) ?? _lastKnown;
    _lastKnown = payout;
    final width = MediaQuery.sizeOf(context).width;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 12 : 28,
        vertical: 24,
      ),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: payout == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('This payout is no longer in the list.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Header(payout: payout)),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: controller.isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Destination(payout: payout),
                          const SizedBox(height: 16),
                          if (payout.status == SellerPayoutStatus.paid)
                            _PaidRecord(payout: payout)
                          else if (payout.status == SellerPayoutStatus.rejected)
                            _InfoBlock(
                              title: 'Rejected',
                              body:
                                  payout.rejectionReason ??
                                  'No reason recorded.',
                              color: AppColors.error,
                            )
                          else if (payout.status ==
                              SellerPayoutStatus.cancelled)
                            _InfoBlock(
                              title: 'Cancelled by the seller',
                              body: payout.cancelledAt == null
                                  ? 'The seller cancelled this request.'
                                  : 'The seller cancelled this request on '
                                        '${formatAdminTableDateTime(payout.cancelledAt!)}.',
                              color: AppColors.textSecondary,
                            )
                          else if (_mode == _DialogMode.reject)
                            _rejectForm(controller, payout)
                          else
                            _transferForm(controller, payout),
                          if (controller.actionError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              controller.actionError!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _actions(controller, payout),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _transferForm(
    AdminSellerPayoutsController controller,
    AdminSellerPayout payout,
  ) {
    final errors = controller.fieldErrors;
    final evidence = controller.evidence;
    final busy = controller.isSubmitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Record transfer', style: AppTypography.sectionTitle),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Amount sent (PHP)',
          hint: (payout.amountCentavos / 100).toStringAsFixed(2),
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
        OutlinedButton.icon(
          onPressed: busy ? null : () => _pickDate(payout),
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(
            _sentAt == null ? 'Choose date' : formatFullDate(_sentAt!),
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
      ],
    );
  }

  String? _rejectFieldError(AdminSellerPayoutsController controller) {
    final fromController = controller.fieldErrors['reason'];
    if (fromController != null) return fromController;
    if (!_rejectAttempted) return null;
    return validatePayoutRejectionSelection(
      reasonId: _rejectReasonId,
      otherDetail: _otherRejectDetail.text,
    );
  }

  Widget _rejectForm(
    AdminSellerPayoutsController controller,
    AdminSellerPayout payout,
  ) {
    final reasonError = _rejectFieldError(controller);
    final otherSelected = _rejectReasonId == kSellerPayoutRejectOtherId;
    final busy = controller.isSubmitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reject request', style: AppTypography.sectionTitle),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _rejectReasonId,
          onChanged: (value) {
            if (busy) return;
            setState(() {
              _rejectReasonId = value;
              _rejectAttempted = false;
            });
          },
          child: Column(
            children: [
              for (final reason in kSellerPayoutRejectReasons)
                RadioListTile<String>(
                  value: reason.id,
                  title: Text(reason.label, style: AppTypography.body),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
        if (otherSelected) ...[
          const SizedBox(height: 4),
          ThriftTextField(
            label: 'Explain for the seller',
            hint: 'What should they fix or know?',
            controller: _otherRejectDetail,
            readOnly: busy,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (reasonError != null) ...[
          const SizedBox(height: 4),
          Text(
            reasonError,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Widget _actions(
    AdminSellerPayoutsController controller,
    AdminSellerPayout payout,
  ) {
    final busy = controller.isSubmitting;
    final close = TextButton(
      onPressed: busy ? null : () => Navigator.of(context).pop(),
      child: Text(payout.isOpen ? 'Cancel' : 'Close'),
    );
    if (!payout.isOpen) {
      return Align(alignment: Alignment.centerRight, child: close);
    }
    if (_mode == _DialogMode.reject) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() => _mode = _DialogMode.view),
            child: const Text('Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: busy ? null : () => _reject(payout),
            child: Text(busy ? 'Rejecting…' : 'Reject payout'),
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
          ),
          onPressed: busy ? null : _enterRejectMode,
          child: const Text('Reject'),
        ),
        close,
        FilledButton(
          onPressed: busy || !payout.hasGcashDestination
              ? null
              : () => _record(payout),
          child: Text(busy ? 'Saving…' : 'Mark as paid'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.payout});

  final AdminSellerPayout payout;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatCentavos(payout.amountCentavos),
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: 4),
              Text(
                payout.sellerDisplayName,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  if (payout.shopName != null) payout.sellerName,
                  if (payout.sellerEmail != null) payout.sellerEmail!,
                ].join(' · '),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (payout.requestedAt != null)
                Text(
                  'Requested ${formatAdminTableDateTime(payout.requestedAt!)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        AdminStatusBadge(
          status: adminPayoutBadgeKey(payout.status),
          label: adminPayoutStatusLabel(payout.status),
        ),
      ],
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({required this.payout});

  final AdminSellerPayout payout;

  @override
  Widget build(BuildContext context) {
    if (!payout.hasGcashDestination) {
      return const _InfoBlock(
        title: 'GCash details missing',
        body:
            'This request has no GCash account saved. Reject it and ask the '
            'seller to add GCash and request again.',
        color: AppColors.error,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GCash destination',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    payout.gcashAccountName!,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SelectableText(
                    formatPhMobile(payout.gcashMobileNumber),
                    style: AppTypography.body,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy number',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: payout.gcashMobileNumber ?? ''),
                );
                showThriftSnackBar(context, 'GCash number copied.');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidRecord extends StatelessWidget {
  const _PaidRecord({required this.payout});

  final AdminSellerPayout payout;

  @override
  Widget build(BuildContext context) {
    final evidence = payout.evidencePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Transfer record', style: AppTypography.sectionTitle),
        const SizedBox(height: 8),
        _Row(
          label: 'Amount sent',
          value: formatCentavos(
            payout.transferredAmountCentavos ?? payout.amountCentavos,
          ),
        ),
        _Row(label: 'GCash reference', value: payout.gcashReference ?? '—'),
        if (payout.transferredAt != null)
          _Row(
            label: 'Sent on',
            value: formatAdminTableDateTime(payout.transferredAt!),
          ),
        if (payout.processedAt != null)
          _Row(
            label: 'Recorded on',
            value: formatAdminTableDateTime(payout.processedAt!),
          ),
        if (payout.adminNote != null)
          _Row(label: 'Note', value: payout.adminNote!),
        if (evidence != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View receipt'),
              onPressed: () async {
                final opened = await context
                    .read<AdminSellerPayoutsController>()
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

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(body, style: AppTypography.caption),
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
      padding: const EdgeInsets.only(bottom: 8),
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
          Expanded(child: SelectableText(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}
