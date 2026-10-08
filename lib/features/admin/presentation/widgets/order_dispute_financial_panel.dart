import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_evidence_attempt_rules.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../data/admin_report_decision_content.dart';
import '../../data/admin_review_rules.dart';
import '../../data/delivery_payment_hold.dart';
import '../../data/delivery_payment_resolve.dart';
import '../widgets/admin_review_widgets.dart';
import 'admin_report_decision_widgets.dart';
import 'community_dispute_decision_cards.dart';

enum OrderDisputeFinancialChoice { refundBuyer, releaseSeller, requestEvidence }

/// Order report financial resolution (single-column decision flow).
class OrderDisputeFinancialPanel extends StatefulWidget {
  const OrderDisputeFinancialPanel({
    super.key,
    required this.hold,
    required this.isSaving,
    required this.canSubmitFinancial,
    required this.notesController,
    this.onNotesChanged,
    required this.onConfirmRefund,
    required this.onConfirmRelease,
    required this.onRequestEvidence,
    this.notesError,
    this.report,
    this.order,
    this.reporterPartyHint,
    this.reportedPartyHint,
  });

  final DeliveryPaymentHold? hold;
  final bool isSaving;
  final bool canSubmitFinancial;
  final TextEditingController notesController;
  final ValueChanged<String>? onNotesChanged;
  final Future<DeliveryPaymentResult> Function(bool returnRequired)
  onConfirmRefund;
  final Future<DeliveryPaymentResult> Function() onConfirmRelease;
  final Future<String?> Function(String party, String instruction)
  onRequestEvidence;
  final String? notesError;
  final CommunityReportModel? report;
  final OrderModel? order;
  final String? reporterPartyHint;
  final String? reportedPartyHint;

  @override
  State<OrderDisputeFinancialPanel> createState() =>
      _OrderDisputeFinancialPanelState();
}

class _OrderDisputeFinancialPanelState
    extends State<OrderDisputeFinancialPanel> {
  OrderDisputeFinancialChoice? _choice;
  bool? _returnRequired;
  AdminEvidenceRequestTarget _evidenceTarget =
      AdminEvidenceRequestTarget.reporter;
  final Set<String> _selectedEvidenceTypes = {};
  final _customEvidenceController = TextEditingController();
  final _evidenceMessageController = TextEditingController();
  String _closeTemplateId = kAdminOrderCloseTemplates.first.id;
  String _evidenceIntroTemplateId = kAdminEvidenceRequestTemplates.first.id;

  @override
  void dispose() {
    _customEvidenceController.dispose();
    _evidenceMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    if (hold == null) {
      return Text(
        'No escrow record for this order.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    }

    final report = widget.report;
    final canRequestEvidence = report == null
        ? true
        : canAdminRequestMoreReportEvidence(
            status: report.status,
            evidenceAttemptCount: report.evidenceAttemptCount,
          );
    final evidenceDisabledReason = report == null
        ? null
        : adminEvidenceRequestDisabledReason(
            status: report.status,
            evidenceAttemptCount: report.evidenceAttemptCount,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report != null)
          Text(
            'Evidence rounds completed: ${report.evidenceAttemptCount} of $kReportMaxEvidenceAttempts',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        const SizedBox(height: 12),
        CommunityDisputeDecisionCardGroup(
          selectedValue: _choice == null
              ? null
              : switch (_choice!) {
                  OrderDisputeFinancialChoice.requestEvidence =>
                    'request_evidence',
                  OrderDisputeFinancialChoice.refundBuyer => 'refund_buyer',
                  OrderDisputeFinancialChoice.releaseSeller => 'release_seller',
                },
          onSelected: (value) {
            if (widget.isSaving) return;
            final choice = switch (value) {
              'request_evidence' => OrderDisputeFinancialChoice.requestEvidence,
              'refund_buyer' => OrderDisputeFinancialChoice.refundBuyer,
              'release_seller' => OrderDisputeFinancialChoice.releaseSeller,
              _ => null,
            };
            if (choice != null) _select(choice);
          },
          options: [
            for (final option in kOrderDisputeDecisionOptions)
              CommunityDisputeDecisionOptionData(
                value: option.value,
                title: option.title,
                description: option.description,
                icon: option.icon,
                enabled: option.value == 'request_evidence'
                    ? canRequestEvidence
                    : true,
              ),
          ],
        ),
        if (!canRequestEvidence && evidenceDisabledReason != null) ...[
          const SizedBox(height: 10),
          Text(
            evidenceDisabledReason,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
        if (_choice == OrderDisputeFinancialChoice.requestEvidence)
          _buildEvidenceRequestSection(),
        if (_choice == OrderDisputeFinancialChoice.refundBuyer)
          _buildRefundSection(hold),
        if (_choice == OrderDisputeFinancialChoice.releaseSeller)
          _buildReleaseSection(),
      ],
    );
  }

  Widget _buildRefundSection(DeliveryPaymentHold hold) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Return item?', style: AppTypography.subheading),
          const SizedBox(height: 8),
          AdminChoiceRow(
            label: 'Return required',
            hint: 'Seller arranges pickup',
            selected: _returnRequired == true,
            onTap: widget.isSaving
                ? () {}
                : () => setState(() => _returnRequired = true),
          ),
          AdminChoiceRow(
            label: 'No return',
            hint: 'Item missing or not receivable',
            selected: _returnRequired == false,
            onTap: widget.isSaving
                ? () {}
                : () => setState(() => _returnRequired = false),
          ),
          const SizedBox(height: 16),
          AdminResponseTemplateDropdown(
            templates: kAdminOrderCloseTemplates,
            selectedId: _closeTemplateId,
            enabled: !widget.isSaving,
            onSelected: _applyCloseTemplate,
          ),
          const SizedBox(height: 12),
          AdminEditableGeneratedMessage(
            controller: widget.notesController,
            onChanged: widget.onNotesChanged ?? (_) {},
            error: widget.notesError,
            label: 'Message to reporter',
          ),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Review refund',
            isLoading: widget.isSaving,
            onPressed:
                widget.canSubmitFinancial &&
                    _returnRequired != null &&
                    widget.notesError == null
                ? () => _confirmRefund(context, hold)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminResponseTemplateDropdown(
            templates: kAdminOrderCloseTemplates,
            selectedId: _closeTemplateId,
            enabled: !widget.isSaving,
            onSelected: _applyCloseTemplate,
          ),
          const SizedBox(height: 12),
          AdminEditableGeneratedMessage(
            controller: widget.notesController,
            onChanged: widget.onNotesChanged ?? (_) {},
            error: widget.notesError,
            label: 'Message to reporter',
          ),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Review release',
            isLoading: widget.isSaving,
            onPressed: widget.canSubmitFinancial && widget.notesError == null
                ? () => _confirmRelease(context)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceRequestSection() {
    final reporterHint =
        widget.reporterPartyHint ?? 'User who filed the report';
    final reportedHint = widget.reportedPartyHint ?? 'User being reported';

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Request from', style: AppTypography.subheading),
          const SizedBox(height: 8),
          AdminEvidencePartySelector(
            target: _evidenceTarget,
            reporterLabel: reporterHint,
            reportedLabel: reportedHint,
            enabled: !widget.isSaving,
            onChanged: (v) => setState(() => _evidenceTarget = v),
          ),
          const SizedBox(height: 20),
          Text('Evidence needed', style: AppTypography.subheading),
          const SizedBox(height: 8),
          AdminEvidenceTypeChipSelector(
            selectedIds: _selectedEvidenceTypes,
            enabled: !widget.isSaving,
            onToggle: _toggleEvidenceType,
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Other / custom evidence',
            hint: 'Optional detail not covered above',
            controller: _customEvidenceController,
            maxLines: 2,
            onChanged: (_) => _syncEvidenceMessage(),
          ),
          const SizedBox(height: 12),
          AdminResponseTemplateDropdown(
            templates: kAdminEvidenceRequestTemplates,
            selectedId: _evidenceIntroTemplateId,
            enabled: !widget.isSaving,
            onSelected: (t) {
              setState(() {
                _evidenceIntroTemplateId = t.id;
                _syncEvidenceMessage();
              });
            },
          ),
          const SizedBox(height: 12),
          AdminEditableGeneratedMessage(
            controller: _evidenceMessageController,
            onChanged: (_) => setState(() {}),
            label: 'Generated request message',
            maxLength: kAdminResponseMaxLength,
          ),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Review evidence request',
            variant: ThriftButtonVariant.outline,
            isLoading: widget.isSaving,
            onPressed: _canSendEvidenceRequest
                ? () => _sendEvidenceRequest(context)
                : null,
          ),
        ],
      ),
    );
  }

  void _toggleEvidenceType(String id) {
    setState(() {
      if (_selectedEvidenceTypes.contains(id)) {
        _selectedEvidenceTypes.remove(id);
      } else {
        _selectedEvidenceTypes.add(id);
      }
      _syncEvidenceMessage();
    });
  }

  void _syncEvidenceMessage() {
    final labels = kAdminEvidenceTypeOptions
        .where((o) => _selectedEvidenceTypes.contains(o.id))
        .map((o) => o.label)
        .toList();
    final intro = kAdminEvidenceRequestTemplates
        .firstWhere((t) => t.id == _evidenceIntroTemplateId)
        .message;
    final text = buildEvidenceRequestInstruction(
      selectedTypeLabels: labels,
      customDetail: _customEvidenceController.text,
      intro: intro,
    );
    _evidenceMessageController.text = text;
    setState(() {});
  }

  void _applyCloseTemplate(AdminResponseTemplate template) {
    setState(() {
      _closeTemplateId = template.id;
      if (template.message.isNotEmpty) {
        widget.notesController.text = template.message;
        widget.onNotesChanged?.call(template.message);
      }
    });
  }

  bool get _canSendEvidenceRequest {
    final t = _evidenceMessageController.text.trim();
    return !widget.isSaving &&
        t.length >= kAdminNeedsMoreEvidenceMinLength &&
        t.length <= kAdminResponseMaxLength &&
        (_selectedEvidenceTypes.isNotEmpty ||
            _customEvidenceController.text.trim().isNotEmpty);
  }

  void _select(OrderDisputeFinancialChoice choice) {
    setState(() {
      _choice = choice;
      if (choice != OrderDisputeFinancialChoice.refundBuyer) {
        _returnRequired = null;
      }
      if (choice == OrderDisputeFinancialChoice.requestEvidence) {
        _syncEvidenceMessage();
      }
      if (choice == OrderDisputeFinancialChoice.refundBuyer ||
          choice == OrderDisputeFinancialChoice.releaseSeller) {
        final template = kAdminOrderCloseTemplates.firstWhere(
          (t) => t.id == _closeTemplateId,
          orElse: () => kAdminOrderCloseTemplates.first,
        );
        if (template.message.isNotEmpty &&
            widget.notesController.text.trim().isEmpty) {
          _applyCloseTemplate(template);
        }
      }
    });
  }

  String _apiParty() {
    final report = widget.report;
    if (report == null) {
      return _evidenceTarget == AdminEvidenceRequestTarget.reporter
          ? 'reporter'
          : 'buyer';
    }
    return adminEvidencePartyApiValue(
      target: _evidenceTarget,
      reporterId: report.reporterId,
      reportedUserId: report.reportedUserId,
      orderBuyerId: widget.order?.buyerId,
      orderSellerId: widget.order?.sellerId,
    );
  }

  String _partySummaryLabel() {
    if (_evidenceTarget == AdminEvidenceRequestTarget.reporter) {
      return 'Reporter — ${widget.reporterPartyHint ?? '—'}';
    }
    return 'Reported user — ${widget.reportedPartyHint ?? '—'}';
  }

  Future<void> _confirmRefund(
    BuildContext context,
    DeliveryPaymentHold hold,
  ) async {
    final returnRequired = _returnRequired;
    if (returnRequired == null) return;
    final amount = formatCentavos(hold.amountCentavos);
    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Confirm refund',
      confirmLabel: 'Confirm refund',
      destructive: true,
      rows: [
        ('Action', 'Refund buyer'),
        ('Amount', amount),
        (
          'Return',
          returnRequired
              ? 'Return required — seller arranges pickup'
              : 'No return required',
        ),
        ('Message', widget.notesController.text.trim()),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    final result = await widget.onConfirmRefund(returnRequired);
    if (!context.mounted) return;
    _showPaymentSnack(
      context,
      result,
      refunded: true,
      returnRequired: returnRequired,
    );
  }

  Future<void> _confirmRelease(BuildContext context) async {
    final hold = widget.hold!;
    final amount = formatCentavos(hold.amountCentavos);
    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Confirm release to seller',
      confirmLabel: 'Confirm release',
      rows: [
        ('Action', 'Release payment to seller'),
        ('Amount', amount),
        ('Message', widget.notesController.text.trim()),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    final result = await widget.onConfirmRelease();
    if (!context.mounted) return;
    _showPaymentSnack(context, result, refunded: false);
  }

  Future<void> _sendEvidenceRequest(BuildContext context) async {
    final instruction = _evidenceMessageController.text.trim();
    final evidenceLabels = kAdminEvidenceTypeOptions
        .where((o) => _selectedEvidenceTypes.contains(o.id))
        .map((o) => o.label)
        .join(', ');
    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Confirm evidence request',
      confirmLabel: 'Send request',
      rows: [
        ('Action', 'Request more evidence'),
        ('Request from', _partySummaryLabel()),
        ('Evidence needed', evidenceLabels),
        ('Message', instruction),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    final error = await widget.onRequestEvidence(_apiParty(), instruction);
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Evidence request sent. Escrow stays on hold.');
  }

  void _showPaymentSnack(
    BuildContext context,
    DeliveryPaymentResult result, {
    required bool refunded,
    bool returnRequired = false,
  }) {
    if (!result.success) {
      showThriftSnackBar(
        context,
        result.error ?? 'Could not complete this resolution.',
        isError: true,
      );
      return;
    }
    if (refunded) {
      showThriftSnackBar(
        context,
        returnRequired
            ? 'Buyer refunded. Seller must arrange the return.'
            : 'Buyer refunded. No return required.',
      );
    } else {
      showThriftSnackBar(
        context,
        'Payment released to the seller. Case closed.',
      );
    }
  }
}
