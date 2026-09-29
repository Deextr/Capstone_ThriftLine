import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../controllers/admin_seller_applications_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_verification_service.dart';
import '../widgets/admin_review_widgets.dart';

final _countFormat = NumberFormat.decimalPattern();

class AdminSellerApplicationsScreen extends StatelessWidget {
  const AdminSellerApplicationsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminSellerApplicationsController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;
    final bottomPad = embedded && !wideNav ? 112.0 : 32.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(embedded ? 'Seller Verifications' : 'Seller Applications'),
        automaticallyImplyLeading: !embedded,
        leading: embedded
            ? null
            : IconButton(
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
          child: controller.isLoading && !controller.hasLoadedCounts
              ? const _VerificationsSkeleton()
              : controller.errorMessage != null && !controller.hasLoadedCounts
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
                  : _VerificationsContent(
                      controller: controller,
                      bottomPad: bottomPad,
                    ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton shown on the very first load before any data is available.
// ---------------------------------------------------------------------------

class _VerificationsSkeleton extends StatelessWidget {
  const _VerificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: const [
        // Pending card placeholder
        ShimmerBox(width: double.infinity, height: 200, radius: 12),
        SizedBox(height: 12),
        // Approved + Rejected row placeholder
        Row(
          children: [
            Expanded(
              child: ShimmerBox(
                width: double.infinity,
                height: 130,
                radius: 12,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ShimmerBox(
                width: double.infinity,
                height: 130,
                radius: 12,
              ),
            ),
          ],
        ),
        SizedBox(height: 24),
        ShimmerBox(width: 148, height: 14),
        SizedBox(height: 16),
        ShimmerBox(width: double.infinity, height: 72, radius: 12),
        SizedBox(height: 8),
        ShimmerBox(width: double.infinity, height: 72, radius: 12),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main content: verification status cards + filtered application list.
// ---------------------------------------------------------------------------

class _VerificationsContent extends StatelessWidget {
  const _VerificationsContent({
    required this.controller,
    required this.bottomPad,
  });

  final AdminSellerApplicationsController controller;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final emptyTitle = switch (controller.filter) {
      AdminDashboardVerificationFilter.pending =>
        'No seller applications waiting for review.',
      AdminDashboardVerificationFilter.approved =>
        'No approved seller applications.',
      AdminDashboardVerificationFilter.rejected =>
        'No rejected seller applications.',
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
      children: [
        // ── Large Pending Verification Card ──
        _PendingVerificationCard(
          count: controller.pendingCount,
          isSelected:
              controller.filter == AdminDashboardVerificationFilter.pending,
          onTap: () => context
              .read<AdminSellerApplicationsController>()
              .setFilter(AdminDashboardVerificationFilter.pending),
        ),
        const SizedBox(height: 12),

        // ── Approved + Rejected row ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatusCard(
                label: 'Approved',
                count: controller.approvedCount,
                icon: Icons.check_circle_outline_rounded,
                accentColor: AppColors.success,
                isSelected: controller.filter ==
                    AdminDashboardVerificationFilter.approved,
                onTap: () => context
                    .read<AdminSellerApplicationsController>()
                    .setFilter(AdminDashboardVerificationFilter.approved),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatusCard(
                label: 'Rejected',
                count: controller.rejectedCount,
                icon: Icons.cancel_outlined,
                accentColor: AppColors.error,
                isSelected: controller.filter ==
                    AdminDashboardVerificationFilter.rejected,
                onTap: () => context
                    .read<AdminSellerApplicationsController>()
                    .setFilter(AdminDashboardVerificationFilter.rejected),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Filtered application list ──
        if (controller.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          )
        else if (controller.errorMessage != null)
          AdminErrorState(
            message: controller.errorMessage!,
            onRetry: () =>
                context.read<AdminSellerApplicationsController>().load(),
          )
        else if (controller.applications.isEmpty)
          AdminEmptyState(
            title: emptyTitle,
            message: 'New applications will appear here.',
          )
        else ...[
          Text(
            adminQueueStatusLine(
              controller.applications.length,
              adminDashboardVerificationFilterLabel(
                controller.filter,
              ).toLowerCase(),
            ),
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < controller.applications.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ApplicationRow(application: controller.applications[i]),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Large Pending Verifications card — hero placement at the top.
// ---------------------------------------------------------------------------

class _PendingVerificationCard extends StatelessWidget {
  const _PendingVerificationCard({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPending = count > 0;

    return Semantics(
      button: true,
      label: 'Pending verifications, ${_countFormat.format(count)}',
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          side: BorderSide(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        elevation: isSelected ? 2 : 0,
        shadowColor: isSelected
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasPending
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.pending_actions_rounded,
                        size: 24,
                        color:
                            hasPending ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                    const Spacer(),
                    if (hasPending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 6,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Needs Attention',
                              style: AppTypography.label.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _countFormat.format(count),
                  style: AppTypography.display.copyWith(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: hasPending ? AppColors.primary : AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pending Verifications',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPending
                      ? 'Applications awaiting your review'
                      : 'No applications currently waiting',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      hasPending ? 'Review Applications' : 'View Pending',
                      style: AppTypography.label.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Smaller status card used for Approved and Rejected.
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${_countFormat.format(count)}',
      child: Material(
        color: isSelected
            ? accentColor.withValues(alpha: 0.04)
            : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          side: BorderSide(
            color: isSelected
                ? accentColor.withValues(alpha: 0.5)
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        elevation: isSelected ? 2 : 0,
        shadowColor: isSelected
            ? accentColor.withValues(alpha: 0.15)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: accentColor),
                ),
                const SizedBox(height: 12),
                Text(
                  _countFormat.format(count),
                  style: AppTypography.heading.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTypography.label.copyWith(
                    color:
                        isSelected ? accentColor : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single application row (preserved from the original screen).
// ---------------------------------------------------------------------------

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
      actionLabel: application.status == 'pending'
          ? 'Review application'
          : 'View application',
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
