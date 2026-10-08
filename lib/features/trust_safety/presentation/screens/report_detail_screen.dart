import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/report_status.dart';
import '../../../../models/community_report_model.dart';
import '../../../../models/enums.dart';
import '../../../../models/order_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/my_reports_controller.dart';
import '../../data/report_evidence_attempt_rules.dart';
import '../../data/report_reasons.dart';
import '../widgets/report_evidence_section.dart';

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyReportsController>();
    final report = controller.report;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Report details'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: controller.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : report == null
            ? _ErrorBody(
                message: controller.errorMessage ?? 'Report not found.',
                onRetry: () => context.read<MyReportsController>().load(),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<MyReportsController>().load(
                  showSpinner: false,
                ),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _ReportStatusCard(status: report.status),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Report information',
                      children: [
                        _InfoRow(
                          label: 'Reference',
                          value: reportReferenceLabel(report.id),
                        ),
                        _InfoRow(
                          label: 'Submitted',
                          value: formatFullDate(report.createdAt),
                        ),
                        _InfoRow(
                          label: 'Reason',
                          value: reportReasonLabel(report.category),
                        ),
                        _InfoRow(
                          label: 'Reported member',
                          value: _reportedMemberLabel(report),
                        ),
                        if (report.resolvedAt != null &&
                            reportStatusIsClosed(report.status))
                          _InfoRow(
                            label: 'Review completed',
                            value: formatFullDate(report.resolvedAt!),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Your report',
                      children: [
                        Text(
                          report.details.trim().isEmpty
                              ? 'No additional details were provided.'
                              : report.details.trim(),
                          style: AppTypography.body.copyWith(height: 1.45),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _EvidenceSection(evidence: report.evidence),
                    if (report.orderId != null &&
                        (controller.linkedOrder != null ||
                            (report.orderNumber?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 20),
                      _RelatedOrderSection(
                        report: report,
                        order: controller.linkedOrder,
                      ),
                    ],
                    const SizedBox(height: 20),
                    _AdminResponseSection(report: report),
                    if (reportStatusAllowsResubmit(report.status)) ...[
                      const SizedBox(height: 20),
                      _ResubmitEvidenceSection(report: report),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  static String _reportedMemberLabel(CommunityReportModel report) {
    final shop = report.reportedShopName?.trim();
    if (shop != null && shop.isNotEmpty) return shop;
    if (report.reportedUsername.isNotEmpty) {
      return '@${report.reportedUsername}';
    }
    return report.reportedDisplayName;
  }
}

class _ReportStatusCard extends StatelessWidget {
  const _ReportStatusCard({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = reportStatusFromDb(status);
    final color = reportStatusColor(status);
    final icon = reportStatusIcon(status);
    final label = reportStatusLabel(status);
    final description = reportStatusDescription(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report status',
            style: AppTypography.caption.copyWith(
              color: AppColors.textHint,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.subheading.copyWith(
                        fontSize: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (normalized == 'under_review') ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can leave this page—we will notify you when your '
                    'report is updated.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.subheading),
          const SizedBox(height: 4),
          const Divider(height: 20, color: AppColors.border),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.evidence});

  final List<ReportEvidenceItem> evidence;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Evidence',
      children: [
        if (evidence.isEmpty)
          Text(
            'No photos were attached to this report.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          )
        else ...[
          Text(
            'Tap a photo to view it full size.',
            style: AppTypography.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < evidence.length; i++)
                _EvidenceThumb(item: evidence[i], index: i + 1),
            ],
          ),
        ],
      ],
    );
  }
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({required this.item, required this.index});

  final ReportEvidenceItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final url = item.signedUrl;
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: url == null ? null : () => _openPreview(context, url),
        child: SizedBox(
          width: 96,
          height: 96,
          child: url == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Photo $index',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$index',
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _openPreview(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RelatedOrderSection extends StatelessWidget {
  const _RelatedOrderSection({required this.report, required this.order});

  final CommunityReportModel report;
  final OrderModel? order;

  @override
  Widget build(BuildContext context) {
    final orderId = report.orderId;
    final title =
        order?.productTitle ??
        report.orderTitle ??
        (orderId != null ? 'Order item' : 'Related order');
    final orderNumber = order?.orderNumber ?? report.orderNumber ?? '';
    final imageUrl = order?.productImage ?? '';
    final seller = order?.sellerName ?? report.reportedShopName ?? '';
    final total = order?.total;
    final status = order?.status;

    return _Section(
      title: 'Related order',
      children: [
        Material(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: orderId == null
                ? null
                : () => context.push(RouteNames.trackOrderFor(orderId)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            color: AppColors.surfaceVariant,
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              color: AppColors.textHint,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (orderNumber.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Order #$orderNumber',
                            style: AppTypography.caption,
                          ),
                        ],
                        if (seller.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            seller,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        if (total != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(total),
                            style: AppTypography.body.copyWith(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (status != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            orderStatusLabel(status),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (orderId != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (orderId != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(RouteNames.trackOrderFor(orderId)),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View order'),
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminResponseSection extends StatelessWidget {
  const _AdminResponseSection({required this.report});

  final CommunityReportModel report;

  @override
  Widget build(BuildContext context) {
    final instruction = report.reporterInstruction?.trim();
    final response = report.adminResponse?.trim();
    final hasInstruction = instruction != null && instruction.isNotEmpty;
    final hasResponse = response != null && response.isNotEmpty;
    final closed = reportStatusIsClosed(report.status);
    final statusColor = reportStatusColor(report.status);

    return _Section(
      title: 'Admin response',
      children: [
        if (hasInstruction) ...[
          Text(
            'More evidence is required',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(instruction, style: AppTypography.body.copyWith(height: 1.45)),
          const SizedBox(height: 8),
          Text(
            'Attempt ${report.evidenceAttemptCount} of $kReportMaxEvidenceAttempts used',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ] else if (!hasResponse && !closed)
          Text(
            'No response yet.\nOur team is still reviewing your report.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          )
        else ...[
          if (hasResponse)
            Text(response, style: AppTypography.body.copyWith(height: 1.45))
          else if (closed)
            Text(
              'Your report has been reviewed. See the decision below.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          if (closed) ...[
            const SizedBox(height: 16),
            Text(
              'Decision',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    reportStatusIcon(report.status),
                    size: 20,
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    reportStatusLabel(report.status),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ResubmitEvidenceSection extends StatelessWidget {
  const _ResubmitEvidenceSection({required this.report});

  final CommunityReportModel report;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyReportsController>();
    final showFinalNotice = isReporterFinalEvidenceSubmissionPending(
      status: report.status,
      evidenceAttemptCount: report.evidenceAttemptCount,
    );

    return _Section(
      title: 'Submit additional evidence',
      children: [
        if (showFinalNotice) ...[
          const _FinalEvidenceSubmissionNotice(),
          const SizedBox(height: 16),
        ],
        ReportEvidenceSection(
          evidence: controller.resubmitEvidence,
          evidenceError: null,
          onAddGallery: () => controller.addResubmitPhoto(ImageSource.gallery),
          onAddCamera: () => controller.addResubmitPhoto(ImageSource.camera),
          onRemove: controller.removeResubmitPhoto,
        ),
        const SizedBox(height: 16),
        ThriftButton(
          label: 'Submit additional evidence',
          isLoading: controller.isResubmitting,
          onPressed: controller.canSubmitResubmit
              ? () async {
                  final error = await context
                      .read<MyReportsController>()
                      .submitAdditionalEvidence();
                  if (!context.mounted) return;
                  if (error != null) {
                    showThriftSnackBar(context, error, isError: true);
                    return;
                  }
                  showThriftSnackBar(
                    context,
                    'Your additional evidence has been submitted.',
                  );
                }
              : null,
        ),
      ],
    );
  }
}

class _FinalEvidenceSubmissionNotice extends StatelessWidget {
  const _FinalEvidenceSubmissionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.warning.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Final Evidence Submission',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This is your last opportunity to submit additional evidence '
                  'for this report. Please review your information and attachments '
                  'carefully before submitting. You will not be able to submit '
                  'more evidence after this.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
            const SizedBox(height: 20),
            ThriftButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
