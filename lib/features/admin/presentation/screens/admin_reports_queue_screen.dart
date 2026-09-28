import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReportsQueueScreen extends StatelessWidget {
  const AdminReportsQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final open = controller.filter == AdminQueueFilter.open;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Community Reports'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: AdminFilterBar(
                value: controller.filter,
                onChanged: (filter) =>
                    context.read<AdminReportsController>().setFilter(filter),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<AdminReportsController>().load(),
                child: controller.isLoading
                    ? const AdminQueueSkeleton()
                    : controller.errorMessage != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          AdminErrorState(
                            message: controller.errorMessage!,
                            onRetry: () =>
                                context.read<AdminReportsController>().load(),
                          ),
                        ],
                      )
                    : controller.reports.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          AdminEmptyState(
                            title: open
                                ? 'No community reports waiting for review.'
                                : 'No reviewed community reports yet.',
                            message: open
                                ? 'New reports will appear here.'
                                : 'Reviewed reports will appear here.',
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          Text(
                            adminQueueStatusLine(
                              controller.reports.length,
                              open ? 'under review' : 'reviewed',
                            ),
                            style: AppTypography.subheading,
                          ),
                          const SizedBox(height: 4),
                          for (
                            var i = 0;
                            i < controller.reports.length;
                            i++
                          ) ...[
                            if (i > 0) const Divider(height: 1),
                            _ReportRow(index: i),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final report = controller.reports[index];
    final evidence = adminEvidenceCountLabel(report.evidence.length);
    final order = report.orderNumber == null
        ? ''
        : 'Order #${report.orderNumber}';

    return AdminQueueItem(
      title: reportReasonLabel(report.category),
      status: report.status,
      statusLabel: reportStatusLabel(report.status),
      lines: [
        adminHandle(report.reportedUsername, report.reportedDisplayName),
        'Reported by ${adminHandle(report.reporterUsername, report.reporterDisplayName)}',
      ],
      meta: [
        formatCompactDate(report.createdAt),
        if (evidence.isNotEmpty) evidence,
        if (order.isNotEmpty) order,
      ].join(' · '),
      actionLabel: 'View report',
      onTap: () => _open(context, report.id),
    );
  }

  Future<void> _open(BuildContext context, String reportId) async {
    await context.push(RouteNames.adminReportDetailFor(reportId));
    if (context.mounted) {
      await context.read<AdminReportsController>().load();
    }
  }
}
