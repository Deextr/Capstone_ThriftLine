import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../../data/admin_marketplace_dashboard.dart';
import '../../data/admin_review_rules.dart';
import '../../domain/admin_dashboard_comparison.dart';
import '../../domain/admin_dashboard_period.dart';
import '../widgets/admin_dashboard_widgets.dart';
import '../widgets/admin_review_widgets.dart';

class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key, this.webEmbedded = false});

  final bool webEmbedded;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final controller = context.watch<AdminDashboardController>();
    final wideNav =
        MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;

    final body = SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<AdminDashboardController>().load(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppConstants.maxContentWidth,
                ),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 20, 20, wideNav ? 32 : 112),
                  children: [
                    if (controller.errorMessage != null &&
                        controller.hasData) ...[
                      AdminDashboardBanner(message: controller.errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    if (controller.errorMessage != null && !controller.hasData)
                      AdminErrorState(
                        message: controller.errorMessage!,
                        onRetry: () =>
                            context.read<AdminDashboardController>().load(),
                      )
                    else if (controller.isLoading)
                      AdminDashboardSkeleton(wide: constraints.maxWidth >= 720)
                    else ...[
                      const _PeriodFilters(),
                      const SizedBox(height: 20),
                      const _KpiRow(),
                      const SizedBox(height: 20),
                      const _RevenueSection(),
                      const SizedBox(height: 20),
                      _OperationsRow(maxWidth: constraints.maxWidth),
                      const SizedBox(height: 20),
                      const _RecentActivity(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (webEmbedded) {
      return ColoredBox(
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.isRefreshing)
              LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: AppColors.border,
              ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isLoading
                ? null
                : () => context.read<AdminDashboardController>().load(),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _PeriodFilters extends StatelessWidget {
  const _PeriodFilters();

  @override
  Widget build(BuildContext context) {
    final period = context.watch<AdminDashboardController>().period;
    return AdminDashboardPeriodBar(
      period: period,
      onSelected: (range) => _select(context, range),
    );
  }

  Future<void> _select(BuildContext context, AdminDashboardRange range) async {
    final controller = context.read<AdminDashboardController>();
    if (range == AdminDashboardRange.custom) {
      final custom = await showAdminDashboardRangePicker(
        context,
        initial: controller.period,
      );
      if (custom != null && context.mounted) {
        await controller.setPeriod(custom);
      }
      return;
    }
    final next = switch (range) {
      AdminDashboardRange.allTime => AdminDashboardPeriod.allTime(),
      AdminDashboardRange.today => AdminDashboardPeriod.today(),
      AdminDashboardRange.weekly => AdminDashboardPeriod.weekly(),
      AdminDashboardRange.monthly => AdminDashboardPeriod.monthly(),
      AdminDashboardRange.yearly => AdminDashboardPeriod.yearly(),
      AdminDashboardRange.custom => controller.period,
    };
    await controller.setPeriod(next);
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final snapshot = controller.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final kpis = snapshot.kpis;
    final label = controller.period.comparisonLabel;
    final cards = [
      AdminKpiTile(
        label: 'New users',
        value: formatDashboardCount(kpis.newUsers),
        caption: 'Registered in this period',
        delta: formatAdminPeriodDelta(
          current: kpis.newUsers,
          previous: kpis.newUsersPrevious,
          comparisonAvailable: snapshot.comparisonAvailable,
          comparisonLabel: label,
          higherIsBetter: true,
          unit: 'user',
        ),
      ),
      AdminKpiTile(
        label: 'Completed orders',
        value: formatDashboardCount(kpis.completedOrders),
        caption: 'Deliveries completed',
        delta: formatAdminPeriodDelta(
          current: kpis.completedOrders,
          previous: kpis.completedOrdersPrevious,
          comparisonAvailable: snapshot.comparisonAvailable,
          comparisonLabel: label,
          higherIsBetter: true,
          unit: 'order',
        ),
      ),
      AdminKpiTile(
        label: 'Platform revenue',
        value: formatDashboardPeso(kpis.platformRevenue),
        caption: 'Fees earned, not buyer payments',
        delta: formatAdminPeriodDelta(
          current: kpis.platformRevenue,
          previous: kpis.platformRevenuePrevious,
          comparisonAvailable: snapshot.comparisonAvailable,
          comparisonLabel: label,
          higherIsBetter: true,
          currency: true,
        ),
      ),
      AdminKpiTile(
        label: 'Paid orders',
        value: formatDashboardCount(kpis.paidOrders),
        caption: 'Paid and not refunded',
        delta: formatAdminPeriodDelta(
          current: kpis.paidOrders,
          previous: kpis.paidOrdersPrevious,
          comparisonAvailable: snapshot.comparisonAvailable,
          comparisonLabel: label,
          higherIsBetter: true,
          unit: 'order',
        ),
      ),
    ];
    return _ResponsiveTiles(children: cards);
  }
}

class _ResponsiveTiles extends StatelessWidget {
  const _ResponsiveTiles({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        return _TileGrid(columns: columns, children: children);
      },
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(
        i,
        i + columns > children.length ? children.length : i + columns,
      );
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < slice.length; c++) ...[
              if (c > 0) const SizedBox(width: 12),
              Expanded(child: slice[c]),
            ],
            for (var fill = slice.length; fill < columns; fill++) ...[
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }
}

class _RevenueSection extends StatelessWidget {
  const _RevenueSection();

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<AdminDashboardController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return AdminRevenueChart(
      points: snapshot.revenueSeries,
      bucket: snapshot.bucket,
      showComparison: snapshot.comparisonAvailable,
    );
  }
}

class _OperationsRow extends StatelessWidget {
  const _OperationsRow({required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final activity = _ActivityPanel();
    const attention = _AttentionPanel();
    if (maxWidth < 900) {
      return Column(
        children: [activity, const SizedBox(height: 12), attention],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: activity),
        const SizedBox(width: 12),
        Expanded(child: attention),
      ],
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<AdminDashboardController>().snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final activity = snapshot.activity;
    return AdminDashboardPanel(
      title: 'Marketplace activity',
      child: Column(
        children: [
          AdminStatLine(
            label: 'New listings',
            value: formatDashboardCount(activity.newListings),
          ),
          AdminStatLine(
            label: 'Seller applications submitted',
            value: formatDashboardCount(activity.sellerApplications),
          ),
          AdminStatLine(
            label: 'Paid auction orders',
            value: formatDashboardCount(activity.paidAuctionOrders),
          ),
          AdminStatLine(
            label: 'Orders awaiting fulfillment',
            value: formatDashboardCount(activity.ordersAwaitingFulfillment),
            note: 'Now',
          ),
        ],
      ),
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel();

  @override
  Widget build(BuildContext context) {
    final attention = context
        .watch<AdminDashboardController>()
        .snapshot
        ?.attention;
    if (attention == null) return const SizedBox.shrink();
    return AdminDashboardPanel(
      title: 'Needs attention',
      subtitle: 'Current backlog',
      child: Column(
        children: [
          AdminAttentionLine(
            label: 'Pending seller verifications',
            count: attention.pendingVerifications,
            onTap: () =>
                _open(context, RouteNames.adminVerificationsStatus('pending')),
          ),
          AdminAttentionLine(
            label: 'Community disputes',
            count: attention.openCommunityDisputes,
            onTap: () => _open(
              context,
              RouteNames.adminReportsOpen(AdminReportKind.community),
            ),
          ),
          AdminAttentionLine(
            label: 'Order disputes',
            count: attention.openOrderDisputes,
            onTap: () => _open(
              context,
              RouteNames.adminReportsOpen(AdminReportKind.order),
            ),
          ),
          AdminAttentionLine(
            label: 'Looking For disputes',
            count: attention.openLookingForDisputes,
            onTap: () => _open(
              context,
              RouteNames.adminReportsOpen(AdminReportKind.lookingFor),
            ),
          ),
          AdminAttentionLine(
            label: 'Active bidding restrictions',
            count: attention.activeBiddingRestrictions,
            onTap: () =>
                _open(context, RouteNames.adminBiddingNeedsAttention()),
          ),
          AdminAttentionLine(
            label: 'Cancelled orders awaiting payment review',
            count: attention.paymentReviews,
            onTap: () => _open(context, RouteNames.adminOrdersPaymentReview()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String route) {
    context.go(route);
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context) {
    final items =
        context.watch<AdminDashboardController>().snapshot?.recentActivity ??
        const <AdminRecentActivity>[];
    return AdminDashboardPanel(
      title: 'Recent activity',
      child: items.isEmpty
          ? const AdminDashboardEmptyLine('No recent marketplace events.')
          : Column(
              children: [
                for (final item in items)
                  AdminActivityRow(
                    item: item,
                    onTap: _routeFor(item) == null
                        ? null
                        : () => context.go(_routeFor(item)!),
                  ),
              ],
            ),
    );
  }

  String? _routeFor(AdminRecentActivity item) {
    if (item.targetId.isEmpty) return null;
    return switch (item.targetType) {
      'verification' => RouteNames.adminReviewFor(item.targetId),
      'report' => RouteNames.adminReportDetailFor(item.targetId),
      'looking_for_report' => RouteNames.adminLookingForReportFor(
        item.targetId,
      ),
      'dispute' => RouteNames.adminDisputeDetailFor(item.targetId),
      'order' => RouteNames.adminOrderDetailModalFor(item.targetId),
      _ => null,
    };
  }
}
