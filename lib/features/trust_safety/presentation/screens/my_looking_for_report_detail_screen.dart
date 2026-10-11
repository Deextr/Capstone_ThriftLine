import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/buyer_looking_for_report_model.dart';
import '../../../../models/community_report_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../controllers/my_looking_for_report_controller.dart';
import '../../data/buyer_report_filters.dart';
import '../../data/report_reasons.dart';

class MyLookingForReportDetailScreen extends StatelessWidget {
  const MyLookingForReportDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyLookingForReportController>();
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
                onRetry: () =>
                    context.read<MyLookingForReportController>().load(),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context
                    .read<MyLookingForReportController>()
                    .load(showSpinner: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _ReportStatusCard(status: report.status),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Report information',
                      children: [
                        _InfoRow(label: 'Type', value: 'Looking For report'),
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
                          value:
                              lookingForReportReasonLabel(report.reason) ??
                              report.reason,
                        ),
                        _InfoRow(
                          label: 'Reported member',
                          value: _memberLabel(report),
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
                    _ReportedPostSection(report: report),
                    const SizedBox(height: 20),
                    _EvidenceSection(evidence: report.evidence),
                    const SizedBox(height: 20),
                    _AdminSection(report: report),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReportStatusCard extends StatelessWidget {
  const _ReportStatusCard({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = reportStatusColor(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(reportStatusIcon(status), color: color, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reportStatusLabel(status),
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  reportStatusDescription(status),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
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

class _ReportedPostSection extends StatelessWidget {
  const _ReportedPostSection({required this.report});

  final BuyerLookingForReportModel report;

  @override
  Widget build(BuildContext context) {
    final supabase = context.read<SupabaseService>();
    final path = report.snapshotImagePath?.trim();
    final imageUrl = path != null && path.isNotEmpty
        ? supabase.client.storage.from('looking-for').getPublicUrl(path)
        : '';

    return _Section(
      title: 'Reported request',
      children: [
        Text(
          report.displayPostTitle.isNotEmpty
              ? report.displayPostTitle
              : 'Untitled request',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        ),
        if (report.displayPostDescription.isNotEmpty) ...[
          SizedBox(height: 8),
          Text(
            report.displayPostDescription,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
        if (imageUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () =>
              context.push(RouteNames.lookingForPost(report.postId)),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('View request'),
        ),
      ],
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.evidence});

  final List<ReportEvidenceItem> evidence;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Submitted evidence',
      children: [
        if (evidence.isEmpty)
          Text(
            'No photos were attached to this report.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: evidence.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final item = evidence[index];
                final url = item.signedUrl;
                if (url == null || url.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AdminSection extends StatelessWidget {
  const _AdminSection({required this.report});

  final BuyerLookingForReportModel report;

  @override
  Widget build(BuildContext context) {
    final instruction = report.reporterInstruction?.trim();
    final hasInstruction = instruction != null && instruction.isNotEmpty;
    final closed = reportStatusIsClosed(report.status);
    final statusColor = reportStatusColor(report.status);
    final outcome = buyerLookingForDecisionOutcomeLabel(report.decisionOutcome);

    return _Section(
      title: 'Admin response',
      children: [
        if (hasInstruction) ...[
          Text(
            'More evidence is required',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(instruction, style: AppTypography.body.copyWith(height: 1.45)),
          const SizedBox(height: 8),
          Text(
            'Attempt ${report.evidenceAttemptCount} of $kReportMaxEvidenceAttempts used',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ] else if (!closed)
          Text(
            'No response yet.\nOur team is still reviewing your report.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          )
        else ...[
          Text(
            closed
                ? 'Your report has been reviewed. See the decision below.'
                : '',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (outcome.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(outcome, style: AppTypography.body.copyWith(height: 1.45)),
          ],
          const SizedBox(height: 16),
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
                SizedBox(width: 10),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
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
              style: AppTypography.body.copyWith(height: 1.35),
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _memberLabel(BuyerLookingForReportModel report) {
  if (report.reportedUsername.isNotEmpty) {
    return '@${report.reportedUsername}';
  }
  return report.reportedDisplayName;
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
          SizedBox(height: 4),
          Divider(height: 20, color: AppColors.border),
          ...children,
        ],
      ),
    );
  }
}
