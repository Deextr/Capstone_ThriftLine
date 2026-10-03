import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/empty_state.dart';
import '../../../buyer/domain/looking_for_lifecycle.dart';
import '../../../trust_safety/data/report_reasons.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/looking_for_moderation.dart';
import '../widgets/admin_reports_widgets.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReportsQueueScreen extends StatefulWidget {
  const AdminReportsQueueScreen({
    super.key,
    required this.kind,
    this.embedded = false,
    this.onBackToHub,
  });

  final AdminReportKind kind;
  final bool embedded;
  final VoidCallback? onBackToHub;

  @override
  State<AdminReportsQueueScreen> createState() =>
      _AdminReportsQueueScreenState();
}

class _AdminReportsQueueScreenState extends State<AdminReportsQueueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncKind());
  }

  @override
  void didUpdateWidget(covariant AdminReportsQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _syncKind();
    }
  }

  void _syncKind() {
    if (!mounted) return;
    final controller = context.read<AdminReportsController>();
    if (controller.kind != widget.kind) {
      controller.openCategoryList(widget.kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final read = context.read<AdminReportsController>();
    final showingLookingFor = widget.kind == AdminReportKind.lookingFor;
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final bottomPad = widget.embedded && !wideNav ? 112.0 : 32.0;
    final visible = controller.visibleReports;
    final lookingFor = controller.visibleLookingForReports;
    final summary = controller.kindSummary(widget.kind);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(adminReportKindLabel(widget.kind)),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(context, read),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading ? null : read.load,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: read.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adminReportKindHubSubtitle(widget.kind),
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AdminReportStatusOverview(
                        summary: summary,
                        selected: controller.filter,
                        onSelected: read.setFilter,
                      ),
                      const SizedBox(height: 16),
                      const AdminReportsListFilters(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (controller.isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(const [
                      ShimmerBox(width: 148, height: 14),
                      SizedBox(height: 20),
                      ShimmerBox(
                        width: double.infinity,
                        height: 88,
                        radius: 12,
                      ),
                      SizedBox(height: 10),
                      ShimmerBox(
                        width: double.infinity,
                        height: 88,
                        radius: 12,
                      ),
                    ]),
                  ),
                )
              else if (controller.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AdminErrorState(
                    message: controller.errorMessage!,
                    onRetry: read.load,
                  ),
                )
              else if (showingLookingFor ? lookingFor.isEmpty : visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AdminEmptyState(
                    title: _emptyTitle(controller, widget.kind),
                    message: _emptyMessage(controller, widget.kind),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showingLookingFor) {
                          if (index.isOdd) return const SizedBox(height: 10);
                          final report = lookingFor[index ~/ 2];
                          return AdminReportCard(
                            reportId: report.id,
                            kindLabel: 'Looking For',
                            reporterName: adminHandle(
                              report.reporterUsername,
                              report.reporterName,
                            ),
                            reporterRole: accountRoleLabel(report.reporterRole),
                            reportedName: adminHandle(
                              report.reportedUsername,
                              report.reportedName,
                            ),
                            reportedRole: accountRoleLabel(report.reportedRole),
                            reason:
                                lookingForReportReasonLabel(report.reason) ??
                                report.reason,
                            preview: report.postTitle,
                            status: report.status,
                            statusLabel: lookingForAdminStatusLabel(
                              report.status,
                            ),
                            createdAt: report.createdAt,
                            onView: () => _openLookingFor(context, report.id),
                          );
                        }
                        if (index.isOdd) return const SizedBox(height: 10);
                        final report = visible[index ~/ 2];
                        return AdminReportCard(
                          reportId: report.id,
                          kindLabel: adminReportKindOf(
                            category: report.category,
                            orderId: report.orderId,
                          ),
                          reporterName: adminHandle(
                            report.reporterUsername,
                            report.reporterDisplayName,
                          ),
                          reporterRole: accountRoleLabel(report.reporterRole),
                          reportedName: adminHandle(
                            report.reportedUsername,
                            report.reportedDisplayName,
                          ),
                          reportedRole: accountRoleLabel(report.reportedRole),
                          reason: reportReasonLabel(report.category),
                          preview: adminReportPreview(report.details),
                          status: report.status,
                          statusLabel: reportStatusLabel(report.status),
                          createdAt: report.createdAt,
                          orderNumber: report.orderNumber,
                          onView: () => _open(context, report.id),
                        );
                      },
                      childCount: showingLookingFor
                          ? (lookingFor.isEmpty ? 0 : lookingFor.length * 2 - 1)
                          : (visible.isEmpty ? 0 : visible.length * 2 - 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context, AdminReportsController read) {
    read.leaveCategoryList();
    if (widget.onBackToHub != null) {
      widget.onBackToHub!();
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(RouteNames.adminReports);
  }
}

String _emptyTitle(AdminReportsController controller, AdminReportKind kind) {
  if (kind == AdminReportKind.lookingFor) {
    return controller.lookingForReports.isEmpty
        ? 'No Looking For reports'
        : 'No matching reports';
  }
  final inKind = controller.reports.where(
    (r) => controller.matchesKind(r),
  );
  if (inKind.isEmpty) {
    return switch (kind) {
      AdminReportKind.community => 'No community reports',
      AdminReportKind.order => 'No order reports',
      AdminReportKind.lookingFor => 'No Looking For reports',
      AdminReportKind.all => 'No reports',
    };
  }
  return 'No matching reports';
}

String _emptyMessage(AdminReportsController controller, AdminReportKind kind) {
  if (kind == AdminReportKind.lookingFor) {
    return controller.lookingForReports.isEmpty
        ? 'Reports about Looking For requests will appear here.'
        : 'Try a different status filter or search term.';
  }
  final inKind = controller.reports.where(
    (r) => controller.matchesKind(r),
  );
  if (inKind.isEmpty) {
    return switch (kind) {
      AdminReportKind.community =>
        'No community reports have been submitted yet.',
      AdminReportKind.order => 'No order-related reports have been submitted.',
      AdminReportKind.lookingFor =>
        'Reports about Looking For requests will appear here.',
      AdminReportKind.all => 'New reports will appear here.',
    };
  }
  return 'Try a different status filter, date range, or search term.';
}

Future<void> _openLookingFor(BuildContext context, String reportId) async {
  await context.push(RouteNames.adminLookingForReportFor(reportId));
  if (context.mounted) {
    await context.read<AdminReportsController>().load();
  }
}

Future<void> _open(BuildContext context, String reportId) async {
  await context.push(RouteNames.adminReportDetailFor(reportId));
  if (context.mounted) {
    await context.read<AdminReportsController>().load();
  }
}
