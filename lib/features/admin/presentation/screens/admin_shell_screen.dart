import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../../widgets/empty_state.dart';
import '../../controllers/admin_review_center_controller.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_review_service.dart';
import '../widgets/admin_review_widgets.dart';

class AdminShellScreen extends StatelessWidget {
  const AdminShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final controller = context.watch<AdminReviewCenterController>();
    final counts = controller.counts;
    final name = auth.user?.name.trim() ?? '';

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
            onPressed: () => confirmAndLogout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<AdminReviewCenterController>().load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              if (name.isNotEmpty) ...[
                Text('Signed in as $name', style: AppTypography.caption),
                const SizedBox(height: 20),
              ],
              if (controller.errorMessage != null)
                AdminErrorState(
                  message: controller.errorMessage!,
                  onRetry: () =>
                      context.read<AdminReviewCenterController>().load(),
                )
              else if (controller.isLoading && counts == null)
                const _QueueSkeleton()
              else ...[
                _QueueSurface(
                  children: [
                    AdminQueueNavRow(
                      label: 'Seller Applications',
                      detail: adminQueueStatusLine(
                        counts?.sellerApplications ?? 0,
                        'awaiting review',
                      ),
                      loading: counts == null,
                      needsAttention: (counts?.sellerApplications ?? 0) > 0,
                      icon: Icons.storefront_outlined,
                      semanticLabel: _queueSemantics(
                        'Seller Applications',
                        counts?.sellerApplications,
                        'awaiting review',
                      ),
                      onTap: () => _open(context, RouteNames.adminApplications),
                    ),
                    AdminQueueNavRow(
                      label: 'Community Reports',
                      detail: adminQueueStatusLine(
                        counts?.communityReports ?? 0,
                        'under review',
                      ),
                      loading: counts == null,
                      needsAttention: (counts?.communityReports ?? 0) > 0,
                      icon: Icons.flag_outlined,
                      semanticLabel: _queueSemantics(
                        'Community Reports',
                        counts?.communityReports,
                        'under review',
                      ),
                      onTap: () => _open(context, RouteNames.adminReports),
                    ),
                    AdminQueueNavRow(
                      label: 'Delivery Problems',
                      detail: adminQueueStatusLine(
                        counts?.deliveryProblems ?? 0,
                        'open',
                      ),
                      loading: counts == null,
                      needsAttention: (counts?.deliveryProblems ?? 0) > 0,
                      icon: Icons.local_shipping_outlined,
                      semanticLabel: _queueSemantics(
                        'Delivery Problems',
                        counts?.deliveryProblems,
                        'open',
                      ),
                      onTap: () => _open(context, RouteNames.adminDisputes),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Recent activity', style: AppTypography.subheading),
                const SizedBox(height: 8),
                if (controller.activity.isEmpty)
                  Text(
                    'No recent decisions.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  for (final item in controller.activity) ...[
                    _ActivityRow(
                      item: item,
                      onTap: () => _open(context, _activityRoute(item)),
                    ),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _queueSemantics(String label, int? count, String state) {
    if (count == null) return '$label, loading count';
    return '$label, ${adminQueueStatusLine(count, state)}';
  }

  String _activityRoute(AdminReviewActivity item) {
    return switch (item.target) {
      AdminActivityTarget.application => RouteNames.adminReviewFor(item.id),
      AdminActivityTarget.report => RouteNames.adminReportDetailFor(item.id),
      AdminActivityTarget.dispute => RouteNames.adminDisputeDetailFor(item.id),
    };
  }

  Future<void> _open(BuildContext context, String route) async {
    await context.push(route);
    if (context.mounted) {
      await context.read<AdminReviewCenterController>().load();
    }
  }
}

class _QueueSurface extends StatelessWidget {
  const _QueueSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 48),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _QueueSurface(
      children: [_SkeletonNavRow(), _SkeletonNavRow(), _SkeletonNavRow()],
    );
  }
}

class _SkeletonNavRow extends StatelessWidget {
  const _SkeletonNavRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          ShimmerBox(width: 20, height: 20, radius: 4),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 160, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 112, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.onTap});

  final AdminReviewActivity item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (item.detail.trim().isNotEmpty) item.detail.trim(),
      formatCompactDate(item.occurredAt),
    ].join(' · ');

    return Semantics(
      button: true,
      label: '${item.title}. $detail',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: AppTypography.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
