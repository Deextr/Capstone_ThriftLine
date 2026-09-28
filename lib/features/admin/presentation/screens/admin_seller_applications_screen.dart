import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_seller_applications_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_verification_service.dart';
import '../widgets/admin_review_widgets.dart';

class AdminSellerApplicationsScreen extends StatelessWidget {
  const AdminSellerApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminSellerApplicationsController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seller Applications'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () =>
              context.read<AdminSellerApplicationsController>().load(),
          child: controller.isLoading
              ? const AdminQueueSkeleton()
              : controller.errorMessage != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    AdminErrorState(
                      message: controller.errorMessage!,
                      onRetry: () => context
                          .read<AdminSellerApplicationsController>()
                          .load(),
                    ),
                  ],
                )
              : controller.applications.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    AdminEmptyState(
                      title: 'No seller applications waiting for review.',
                      message: 'New applications will appear here.',
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Text(
                      adminQueueStatusLine(
                        controller.applications.length,
                        'awaiting review',
                      ),
                      style: AppTypography.subheading,
                    ),
                    const SizedBox(height: 8),
                    for (
                      var i = 0;
                      i < controller.applications.length;
                      i++
                    ) ...[
                      if (i > 0) const Divider(height: 1),
                      _ApplicationRow(application: controller.applications[i]),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.application});

  final SellerApplication application;

  @override
  Widget build(BuildContext context) {
    final location = [
      application.barangay,
      application.city,
    ].where((part) => part.trim().isNotEmpty).join(', ');

    return AdminQueueItem(
      title: application.shopName,
      status: application.status,
      statusLabel: verificationStatusLabel(application.status),
      lines: [application.applicantName ?? 'Applicant', location],
      meta: formatCompactDate(application.submittedAt),
      actionLabel: 'Review application',
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    await context.push(RouteNames.adminReviewFor(application.id));
    if (context.mounted) {
      await context.read<AdminSellerApplicationsController>().load();
    }
  }
}
