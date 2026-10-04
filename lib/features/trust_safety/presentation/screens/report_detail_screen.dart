import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../controllers/my_reports_controller.dart';
import '../../data/report_reasons.dart';

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
            ? Center(
                child: Text(
                  controller.errorMessage ?? 'Report not found.',
                  style: AppTypography.body,
                ),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<MyReportsController>().load(
                  showSpinner: false,
                ),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text(
                      reportReasonLabel(report.category),
                      style: AppTypography.heading.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.reportedUsername.isEmpty
                          ? report.reportedDisplayName
                          : '@${report.reportedUsername}',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StatusChip(status: report.status),
                    const SizedBox(height: 24),
                    Text('Your report', style: AppTypography.subheading),
                    const SizedBox(height: 8),
                    Text(report.details, style: AppTypography.body),
                    if (report.orderNumber != null &&
                        report.orderNumber!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Related order', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      Text('#${report.orderNumber}', style: AppTypography.body),
                    ],
                    if (report.evidence.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Evidence', style: AppTypography.subheading),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in report.evidence)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: item.signedUrl == null
                                  ? Container(
                                      width: 88,
                                      height: 88,
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.image_outlined,
                                        color: AppColors.textHint,
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: item.signedUrl!,
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Status', style: AppTypography.subheading),
                    const SizedBox(height: 8),
                    Text(
                      reportStatusLabel(report.status),
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reportStatusDescription(report.status),
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (report.adminResponse != null &&
                        report.adminResponse!.trim().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Admin Response', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      Text(
                        report.adminResponse!.trim(),
                        style: AppTypography.body,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = reportStatusColor(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          reportStatusLabel(status),
          style: AppTypography.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
