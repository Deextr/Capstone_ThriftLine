import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/community_report_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../trust_safety/data/report_evidence_attempt_rules.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../data/admin_report_decision_content.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_review_service.dart';
import 'admin_report_decision_widgets.dart';
import 'admin_review_widgets.dart';
import 'community_dispute_decision_cards.dart';

/// Opens the modern Community Dispute Review modal on top of the current view.
/// Returns `true` if a decision was submitted, allowing the caller to refresh data
/// while preserving current search, filters, and page index.
Future<bool?> showCommunityDisputeReviewModal({
  required BuildContext context,
  required String reportId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CommunityDisputeReviewModal(reportId: reportId),
  );
}

class CommunityDisputeReviewModal extends StatefulWidget {
  const CommunityDisputeReviewModal({super.key, required this.reportId});

  final String reportId;

  @override
  State<CommunityDisputeReviewModal> createState() =>
      _CommunityDisputeReviewModalState();
}

class _CommunityDisputeReviewModalState
    extends State<CommunityDisputeReviewModal> {
  late final AdminReviewService _service;
  final TextEditingController _responseController = TextEditingController();

  CommunityReportModel? _report;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _submitError;

  String? _selectedDecision;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _service = AdminReviewService(context.read<SupabaseService>());
    _loadReport();
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await _service.getReport(widget.reportId);
      if (!mounted) return;
      if (report == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Dispute case not found.';
        });
        return;
      }

      setState(() {
        _report = report;
        _isLoading = false;
        if (report.adminResponse != null && report.adminResponse!.isNotEmpty) {
          _responseController.text = report.adminResponse!;
        }
        _clearInvalidEvidenceRequestSelection(report);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load dispute details. Please try again.';
      });
    }
  }

  void _clearInvalidEvidenceRequestSelection(CommunityReportModel report) {
    if (_selectedDecision != 'needs_more_evidence') return;
    if (canAdminRequestMoreReportEvidence(
      status: report.status,
      evidenceAttemptCount: report.evidenceAttemptCount,
    )) {
      return;
    }
    _selectedDecision = null;
    _selectedTemplateId = null;
    _responseController.clear();
  }

  void _onSelectDecision(String decision) {
    if (_isSubmitting) return;
    final report = _report;
    if (decision == 'needs_more_evidence' &&
        report != null &&
        !canAdminRequestMoreReportEvidence(
          status: report.status,
          evidenceAttemptCount: report.evidenceAttemptCount,
        )) {
      return;
    }
    setState(() {
      _selectedDecision = decision;
      _submitError = null;

      final templates = adminCommunityDecisionTemplatesFor(decision);
      AdminResponseTemplate? preset;
      for (final t in templates) {
        if (t.id == decision) {
          preset = t;
          break;
        }
      }
      preset ??= templates.firstWhere(
        (t) => t.message.isNotEmpty,
        orElse: () => templates.first,
      );
      _selectedTemplateId = preset.id;
      if (preset.message.isNotEmpty) {
        _responseController.text = preset.message;
      } else {
        _responseController.clear();
      }
    });
  }

  void _onApplyTemplate(AdminResponseTemplate template) {
    if (_isSubmitting) return;
    setState(() {
      _selectedTemplateId = template.id;
      if (template.message.isNotEmpty) {
        _responseController.text = template.message;
      }
    });
  }

  bool get _canSubmit {
    if (_report == null || !canDecideReport(_report!.status)) return false;
    if (_selectedDecision == null) return false;
    if (_isSubmitting) return false;
    if (_selectedDecision == 'needs_more_evidence' &&
        !canAdminRequestMoreReportEvidence(
          status: _report!.status,
          evidenceAttemptCount: _report!.evidenceAttemptCount,
        )) {
      return false;
    }
    final text = _responseController.text.trim();
    return adminResponseError(text, decision: _selectedDecision) == null;
  }

  Future<void> _submitDecision() async {
    if (!_canSubmit || _report == null) return;

    final decision = _selectedDecision!;
    final response = _responseController.text.trim();
    final confirmed = await showAdminDecisionConfirmDialog(
      context: context,
      title: 'Confirm decision',
      confirmLabel: communityDisputeModalActionLabel(decision),
      destructive: decision == 'dismissed',
      rows: [
        ('Action', reportDecisionLabel(decision)),
        ('Message', response),
        (
          'Details',
          adminReportDecisionConfirmBody(decision: decision, orderId: null),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final error = await _service.decideReport(
      reportId: _report!.id,
      decision: _selectedDecision!,
      adminResponse: _responseController.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isSubmitting = false;
        _submitError = error;
      });
      return;
    }

    if (decision == 'needs_more_evidence') {
      showThriftSnackBar(context, 'Evidence request sent to the reporter.');
      setState(() {
        _isSubmitting = false;
        _selectedDecision = null;
        _selectedTemplateId = null;
        _responseController.clear();
        _submitError = null;
      });
      await _loadReport();
      return;
    }

    showThriftSnackBar(context, 'Dispute decision submitted successfully.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(740.0, screenSize.width - 32.0);
    final dialogHeight = math.min(840.0, screenSize.height - 48.0);

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
          minWidth: math.min(dialogWidth, 380.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _buildBody(context)),
            const Divider(height: 1, color: AppColors.border),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Community Dispute Review',
                      style: AppTypography.heading.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_report != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          adminModerationCaseRef(_report!.id),
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AdminStatusChip(status: _report!.status),
                    ],
                  ],
                ),
                if (_report != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Submitted on ${formatAdminTableDateTime(_report!.createdAt)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close (Esc)',
            icon: const Icon(
              Icons.close,
              size: 20,
              color: AppColors.textSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null || _report == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Unable to load report.',
                style: AppTypography.body.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadReport,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final report = _report!;
    final decidable = canDecideReport(report.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Parties: Reporter vs Reported User
          _buildPartiesSection(report),
          const SizedBox(height: 20),

          // 2. Reason & Reporter Statement
          _buildDisputeStatementSection(report),
          const SizedBox(height: 20),

          // 3. Evidence Gallery
          _buildEvidenceSection(report),
          const SizedBox(height: 24),

          // 4. Decision Controls or Final Resolution State
          if (decidable)
            _buildDecisionControls(report)
          else
            _buildClosedResolutionCard(report),
        ],
      ),
    );
  }

  Widget _buildPartiesSection(CommunityReportModel report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 540;
        final leftCard = _PartyCard(
          badgeLabel: 'REPORTER',
          badgeColor: AppColors.info,
          icon: Icons.person_outline_rounded,
          displayName: report.reporterDisplayName.trim().isNotEmpty
              ? report.reporterDisplayName.trim()
              : 'Anonymous User',
          username: report.reporterUsername.trim().isNotEmpty
              ? report.reporterUsername.trim()
              : 'unknown',
          role: report.reporterRole != null
              ? accountRoleLabel(report.reporterRole!)
              : 'Member',
          extraInfo: 'Submitted report',
        );

        final rightCard = _PartyCard(
          badgeLabel: 'REPORTED USER',
          badgeColor: AppColors.warning,
          icon: Icons.shield_outlined,
          displayName: report.reportedDisplayName.trim().isNotEmpty
              ? report.reportedDisplayName.trim()
              : 'User',
          username: report.reportedUsername.trim().isNotEmpty
              ? report.reportedUsername.trim()
              : 'unknown',
          role: report.reportedRole != null
              ? accountRoleLabel(report.reportedRole!)
              : 'Seller',
          extraInfo: report.reportedShopName?.trim().isNotEmpty == true
              ? 'Shop: ${report.reportedShopName!.trim()}'
              : null,
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [leftCard, const SizedBox(height: 12), rightCard],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leftCard),
            const SizedBox(width: 14),
            Expanded(child: rightCard),
          ],
        );
      },
    );
  }

  Widget _buildDisputeStatementSection(CommunityReportModel report) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.report_problem_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dispute Reason',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      reportReasonLabel(report.category),
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            'Reporter Statement',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: const BorderSide(color: AppColors.primary, width: 3),
                top: const BorderSide(color: AppColors.border),
                right: const BorderSide(color: AppColors.border),
                bottom: const BorderSide(color: AppColors.border),
              ),
            ),
            child: Text(
              report.details.trim().isNotEmpty
                  ? report.details.trim()
                  : 'No additional written statement was submitted.',
              style: AppTypography.body.copyWith(
                color: report.details.trim().isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceSection(CommunityReportModel report) {
    final validUrls = report.evidence
        .map((e) => e.signedUrl)
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Supporting Evidence',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${validUrls.length}',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (validUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.image_not_supported_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'No photo evidence was attached to this dispute.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < validUrls.length; i++)
                  _EvidenceThumbnail(url: validUrls[i], index: i + 1),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildClosedResolutionCard(CommunityReportModel report) {
    final isResolved = report.status == 'resolved';
    final isDismissed = report.status == 'dismissed';

    return Container(
      decoration: BoxDecoration(
        color: (isResolved ? AppColors.success : AppColors.surfaceVariant)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isResolved ? AppColors.success : AppColors.border).withValues(
            alpha: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isResolved
                    ? Icons.check_circle_outline
                    : (isDismissed
                          ? Icons.cancel_outlined
                          : Icons.info_outline),
                size: 18,
                color: isResolved ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Resolution Outcome',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              AdminStatusChip(status: report.status),
            ],
          ),
          if (report.resolvedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Closed on ${formatAdminTableDateTime(report.resolvedAt!)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Text(
            'Admin Response',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.adminResponse?.trim().isNotEmpty == true
                ? report.adminResponse!.trim()
                : 'No resolution message was recorded.',
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionControls(CommunityReportModel report) {
    final selected = _selectedDecision;
    final text = _responseController.text.trim();
    final responseError = selected != null && text.isNotEmpty
        ? adminResponseError(text, decision: selected)
        : null;
    final canRequestEvidence = canAdminRequestMoreReportEvidence(
      status: report.status,
      evidenceAttemptCount: report.evidenceAttemptCount,
    );
    final evidenceRequestDisabledReason = adminEvidenceRequestDisabledReason(
      status: report.status,
      evidenceAttemptCount: report.evidenceAttemptCount,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Admin Decision',
            style: AppTypography.subheading.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose one outcome. The reporter is notified when you submit.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Evidence rounds completed: ${report.evidenceAttemptCount} of $kReportMaxEvidenceAttempts',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          CommunityDisputeDecisionCardGroup(
            selectedValue: selected,
            onSelected: _onSelectDecision,
            options: [
              for (final option in kCommunityDisputeDecisionOptions)
                CommunityDisputeDecisionOptionData(
                  value: option.value,
                  title: option.title,
                  description: option.description,
                  icon: option.icon,
                  enabled: option.value == 'needs_more_evidence'
                      ? canRequestEvidence
                      : true,
                ),
            ],
          ),
          if (!canRequestEvidence && evidenceRequestDisabledReason != null) ...[
            const SizedBox(height: 10),
            Text(
              evidenceRequestDisabledReason,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (selected != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey<String>(selected),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 16),
                    Text(
                      communityDisputeDecisionFormTitle(selected),
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      communityDisputeDecisionFormHint(selected),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Message to reporter',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Min ${selected == 'needs_more_evidence' ? kAdminNeedsMoreEvidenceMinLength : kAdminResponseMinLength} chars',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AdminResponseTemplateDropdown(
                      templates: adminCommunityDecisionTemplatesFor(selected),
                      selectedId:
                          _selectedTemplateId ??
                          adminCommunityDecisionTemplatesFor(selected).first.id,
                      enabled: !_isSubmitting,
                      onSelected: _onApplyTemplate,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _responseController,
                      enabled: !_isSubmitting,
                      maxLines: 4,
                      minLines: 3,
                      style: AppTypography.body,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Write the message the reporter will see…',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        filled: true,
                        fillColor: AppColors.background,
                        errorText: responseError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _submitError!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final decidable = _report != null && canDecideReport(_report!.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(decidable ? 'Cancel' : 'Close'),
          ),
          if (decidable) ...[
            const SizedBox(width: 12),
            ThriftButton(
              label: _submitButtonLabel,
              isLoading: _isSubmitting,
              expand: false,
              onPressed: _canSubmit ? _submitDecision : null,
            ),
          ],
        ],
      ),
    );
  }

  String get _submitButtonLabel {
    final decision = _selectedDecision;
    if (decision == null) return 'Choose an action';
    return communityDisputeModalActionLabel(decision);
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.badgeLabel,
    required this.badgeColor,
    required this.icon,
    required this.displayName,
    required this.username,
    required this.role,
    this.extraInfo,
  });

  final String badgeLabel;
  final Color badgeColor;
  final IconData icon;
  final String displayName;
  final String username;
  final String role;
  final String? extraInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: badgeColor),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: badgeColor,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  role,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayName,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '@$username',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extraInfo != null) ...[
            const SizedBox(height: 6),
            Text(
              extraInfo!,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.url, required this.index});

  final String url;
  final int index;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showAdminImagePreview(context, url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
          color: AppColors.surfaceVariant,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 24,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
