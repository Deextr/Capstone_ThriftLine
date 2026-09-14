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
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    const Center(child: CircularProgressIndicator()),
                  ],
                )
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
                      message:
                          'New Become a Seller submissions will appear here.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  itemCount: controller.applications.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${controller.applications.length} require review',
                          style: AppTypography.caption,
                        ),
                      );
                    }
                    final application = controller.applications[index - 1];
                    return AdminQueueItem(
                      title: application.shopName,
                      status: application.status,
                      statusLabel: verificationStatusLabel(application.status),
                      lines: [
                        application.applicantName ?? 'Applicant',
                        [
                          application.barangay,
                          application.city,
                        ].where((part) => part.trim().isNotEmpty).join(', '),
                      ],
                      meta: formatCompactDate(application.submittedAt),
                      actionLabel: 'Review application',
                      onTap: () => _open(context, application),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    SellerApplication application,
  ) async {
    await context.push(RouteNames.adminReviewFor(application.id));
    if (context.mounted) {
      await context.read<AdminSellerApplicationsController>().load();
    }
  }
}
