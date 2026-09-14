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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AdminFilterBar(
                  value: controller.filter,
                  onChanged: (filter) =>
                      context.read<AdminReportsController>().setFilter(filter),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<AdminReportsController>().load(),
                child: controller.isLoading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
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
                            title: controller.filter == AdminQueueFilter.open
                                ? 'No community reports waiting for review.'
                                : 'No closed community reports yet.',
                            message: controller.filter == AdminQueueFilter.open
                                ? 'New reports will appear here.'
                                : 'Reviewed reports will appear here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                        itemCount: controller.reports.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                controller.filter == AdminQueueFilter.open
                                    ? '${controller.reports.length} require review'
                                    : '${controller.reports.length} reviewed',
                                style: AppTypography.caption,
                              ),
                            );
                          }
                          final report = controller.reports[index - 1];
                          final evidence = adminEvidenceCountLabel(
                            report.evidence.length,
                          );
                          final order = report.orderNumber == null
                              ? ''
                              : 'Order #${report.orderNumber}';
                          return AdminQueueItem(
                            title: reportReasonLabel(report.category),
                            status: report.status,
                            statusLabel: reportStatusLabel(report.status),
                            lines: [
                              'Reported: ${adminHandle(report.reportedUsername, report.reportedDisplayName)}',
                              'By: ${adminHandle(report.reporterUsername, report.reporterDisplayName)}',
                            ],
                            meta: [
                              formatCompactDate(report.createdAt),
                              if (evidence.isNotEmpty) evidence,
                              if (order.isNotEmpty) order,
                            ].join(' · '),
                            actionLabel: 'View report',
                            onTap: () => _open(context, report.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String reportId) async {
    await context.push(RouteNames.adminReportDetailFor(reportId));
    if (context.mounted) {
      await context.read<AdminReportsController>().load();
    }
  }
}
