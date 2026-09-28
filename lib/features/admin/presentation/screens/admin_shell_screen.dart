import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../controllers/admin_review_center_controller.dart';
import '../widgets/admin_review_widgets.dart';

class AdminShellScreen extends StatelessWidget {
  const AdminShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final controller = context.watch<AdminReviewCenterController>();
    final counts = controller.counts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Review Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading
                ? null
                : () => context.read<AdminReviewCenterController>().load(),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go(RouteNames.login);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<AdminReviewCenterController>().load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                'Signed in as ${auth.user?.name ?? 'Admin'}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 8),
              Text(
                'Review seller applications, community reports, and delivery problems.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              if (controller.errorMessage != null)
                AdminErrorState(
                  message: controller.errorMessage!,
                  onRetry: () =>
                      context.read<AdminReviewCenterController>().load(),
                )
              else ...[
                Text('Needs review', style: AppTypography.heading),
                const SizedBox(height: 4),
                Text(
                  'Open queues only. Counts match the lists you will open.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                AdminQueueNavRow(
                  label: 'Seller Applications',
                  count: counts?.sellerApplications,
                  icon: Icons.storefront_outlined,
                  semanticLabel: _queueSemantics(
                    'Seller Applications',
                    counts?.sellerApplications,
                    controller.isLoading,
                  ),
                  onTap: () => _open(context, RouteNames.adminApplications),
                ),
                const Divider(height: 1),
                AdminQueueNavRow(
                  label: 'Community Reports',
                  count: counts?.communityReports,
                  icon: Icons.flag_outlined,
                  semanticLabel: _queueSemantics(
                    'Community Reports',
                    counts?.communityReports,
                    controller.isLoading,
                  ),
                  onTap: () => _open(context, RouteNames.adminReports),
                ),
                const Divider(height: 1),
                AdminQueueNavRow(
                  label: 'Delivery Problems',
                  count: counts?.deliveryProblems,
                  icon: Icons.local_shipping_outlined,
                  semanticLabel: _queueSemantics(
                    'Delivery Problems',
                    counts?.deliveryProblems,
                    controller.isLoading,
                  ),
                  onTap: () => _open(context, RouteNames.adminDisputes),
                ),
                const Divider(height: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _queueSemantics(String label, int? count, bool loading) {
    if (loading || count == null) {
      return '$label, loading count';
    }
    return '$label, $count need review';
  }

  Future<void> _open(BuildContext context, String route) async {
    await context.push(route);
    if (context.mounted) {
      await context.read<AdminReviewCenterController>().load();
    }
  }
}
