import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/empty_state.dart';
import '../../controllers/admin_reports_controller.dart';
import '../../data/admin_review_rules.dart';
import '../widgets/admin_reports_widgets.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReportsHubScreen extends StatelessWidget {
  const AdminReportsHubScreen({
    super.key,
    this.embedded = false,
    this.onCategorySelected,
  });

  final bool embedded;
  final ValueChanged<AdminReportKind>? onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminReportsController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final bottomPad = embedded && !wideNav ? 112.0 : 32.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        automaticallyImplyLeading: !embedded,
        leading: embedded
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        actions: [
          IconButton(
            tooltip: 'Bid risk events',
            icon: const Icon(Icons.gavel_outlined),
            onPressed: () => context.push(RouteNames.adminBidRiskEvents),
          ),
          IconButton(
            tooltip: 'Disabled accounts',
            icon: const Icon(Icons.person_off_outlined),
            onPressed: () => context.push(RouteNames.adminDisabledAccounts),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading
                ? null
                : () => context.read<AdminReportsController>().load(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<AdminReportsController>().load(),
          child: controller.isLoading && controller.reports.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                  children: const [
                    ShimmerBox(width: double.infinity, height: 140, radius: 12),
                    SizedBox(height: 12),
                    ShimmerBox(width: double.infinity, height: 140, radius: 12),
                    SizedBox(height: 12),
                    ShimmerBox(width: double.infinity, height: 140, radius: 12),
                  ],
                )
              : controller.errorMessage != null && controller.reports.isEmpty
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
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                  children: [
                    Text(
                      'Choose a report category',
                      style: AppTypography.subheading,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Review community, order, and Looking For reports in '
                      'separate queues so nothing gets lost in one long list.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AdminReportCategoryCard(
                      kind: AdminReportKind.community,
                      summary: controller.kindSummary(
                        AdminReportKind.community,
                      ),
                      icon: Icons.groups_outlined,
                      loading: controller.isLoading,
                      onTap: () =>
                          _openCategory(context, AdminReportKind.community),
                    ),
                    const SizedBox(height: 12),
                    AdminReportCategoryCard(
                      kind: AdminReportKind.order,
                      summary: controller.kindSummary(AdminReportKind.order),
                      icon: Icons.local_shipping_outlined,
                      loading: controller.isLoading,
                      onTap: () =>
                          _openCategory(context, AdminReportKind.order),
                    ),
                    const SizedBox(height: 12),
                    AdminReportCategoryCard(
                      kind: AdminReportKind.lookingFor,
                      summary: controller.kindSummary(
                        AdminReportKind.lookingFor,
                      ),
                      icon: Icons.manage_search_outlined,
                      loading: controller.isLoading,
                      onTap: () =>
                          _openCategory(context, AdminReportKind.lookingFor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _openCategory(BuildContext context, AdminReportKind kind) {
    context.read<AdminReportsController>().openCategoryList(kind);
    if (onCategorySelected != null) {
      onCategorySelected!(kind);
      return;
    }
    context.push(RouteNames.adminReportsCategoryFor(kind));
  }
}
