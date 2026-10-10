import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/marketplace_report_models.dart';
import '../../domain/marketplace_report_catalog.dart';
import 'admin_ui_components.dart';

class ReportMetricGroup {
  const ReportMetricGroup({required this.title, required this.metrics});

  final String title;
  final List<MarketplaceReportMetric> metrics;
}

List<ReportMetricGroup> marketplaceReportSummaryGroups({
  AdminReportType? reportType,
  MarketplaceReportCategory? sectionCategory,
  required List<MarketplaceReportMetric> metrics,
}) {
  if (metrics.isEmpty) return const [];

  final type = reportType ?? _adminTypeForSection(sectionCategory) ?? AdminReportType.all;

  List<ReportMetricGroup> byKeys(List<(String, List<String>)> specs) {
    final used = <String>{};
    final groups = <ReportMetricGroup>[];
    for (final (title, keys) in specs) {
      final picked = <MarketplaceReportMetric>[];
      for (final key in keys) {
        for (final m in metrics) {
          if (m.key == key && used.add(m.key)) picked.add(m);
        }
      }
      if (picked.isNotEmpty) {
        groups.add(ReportMetricGroup(title: title, metrics: picked));
      }
    }
    final rest = metrics.where((m) => !used.contains(m.key)).toList();
    if (rest.isNotEmpty) {
      groups.add(ReportMetricGroup(title: 'Additional metrics', metrics: rest));
    }
    return groups;
  }

  return switch (type) {
    AdminReportType.verifications => byKeys([
      (
        'Verification summary',
        ['submitted', 'pending', 'approved', 'rejected', 'processed'],
      ),
      (
        'Processing performance',
        ['approval_rate', 'avg_processing_days'],
      ),
    ]),
    AdminReportType.users => byKeys([
      (
        'Account composition',
        [
          'total_marketplace',
          'buyer_only',
          'buyer_and_seller',
          'new_registrations',
          'sellers_approved_period',
        ],
      ),
      (
        'Account status',
        [
          'active_accounts',
          'disabled_accounts',
          'banned_accounts',
          'restrictions_applied',
        ],
      ),
    ]),
    AdminReportType.ordersTransactions => byKeys([
      (
        'Order performance',
        [
          'orders_created',
          'fixed_price',
          'auction_orders',
          'completed_shipments',
          'cancelled_cohort',
          'checkout_sessions',
          'completion_rate',
          'aov',
          'refunded',
        ],
      ),
      (
        'Payments & revenue',
        [
          'successful_payments',
          'gross_payment_volume',
          'gross_order_value',
          'platform_fees_collected',
          'platform_fees_assessed',
          'seller_allocations',
          'released_earnings',
          'pending_escrow',
          'refunds',
          'failed_payments',
          'net_platform_revenue',
        ],
      ),
    ]),
    AdminReportType.bidding => byKeys([
      (
        'Auction performance',
        [
          'created',
          'ended',
          'ended_with_winner',
          'ended_no_bids',
          'winning_paid',
          'winning_unpaid',
          'cancelled',
          'relisted',
        ],
      ),
      (
        'Bidding activity',
        ['bids', 'violations'],
      ),
    ]),
    AdminReportType.disputes => byKeys([
      (
        'Dispute overview',
        ['submitted', 'pending_snapshot', 'needs_evidence'],
      ),
      (
        'Outcomes & resolution',
        [
          'resolved',
          'dismissed',
          'avg_resolution_hours',
          'refund_outcomes',
          'release_outcomes',
        ],
      ),
    ]),
    AdminReportType.security => byKeys([
      (
        'Security & restrictions',
        [
          'bidding_violations',
          'repeat_violators',
          'banned_snapshot',
          'bidding_restricted',
        ],
      ),
      (
        'Administrative activity',
        ['audit_events', 'audit_failed'],
      ),
    ]),
    AdminReportType.all => _splitBalanced('Marketplace overview', metrics),
  };
}

List<MarketplaceReportBreakdown> _reportBreakdownsForDisplay({
  AdminReportType? reportType,
  MarketplaceReportCategory? sectionCategory,
  required List<MarketplaceReportBreakdown> breakdowns,
}) {
  final isUsersReport =
      reportType == AdminReportType.users ||
          sectionCategory == MarketplaceReportCategory.users;
  if (!isUsersReport) return breakdowns;
  return breakdowns
      .where(
        (b) => !b.title.toLowerCase().contains('account status (marketplace'),
      )
      .toList();
}

AdminReportType? _adminTypeForSection(MarketplaceReportCategory? category) =>
    switch (category) {
      MarketplaceReportCategory.verifications => AdminReportType.verifications,
      MarketplaceReportCategory.users => AdminReportType.users,
      MarketplaceReportCategory.orders => AdminReportType.ordersTransactions,
      MarketplaceReportCategory.payments => AdminReportType.ordersTransactions,
      MarketplaceReportCategory.auctions => AdminReportType.bidding,
      MarketplaceReportCategory.disputes => AdminReportType.disputes,
      MarketplaceReportCategory.security => AdminReportType.security,
      MarketplaceReportCategory.overview => AdminReportType.all,
      null => null,
    };

List<ReportMetricGroup> _splitBalanced(String title, List<MarketplaceReportMetric> metrics) {
  if (metrics.length <= 4) {
    return [ReportMetricGroup(title: title, metrics: metrics)];
  }
  final mid = (metrics.length / 2).ceil();
  return [
    ReportMetricGroup(title: title, metrics: metrics.sublist(0, mid)),
    ReportMetricGroup(
      title: 'Continued',
      metrics: metrics.sublist(mid),
    ),
  ];
}

class MarketplaceReportSummaryLayout extends StatelessWidget {
  const MarketplaceReportSummaryLayout({
    super.key,
    this.reportType,
    this.sectionCategory,
    required this.metrics,
    this.breakdowns = const [],
  });

  final AdminReportType? reportType;
  final MarketplaceReportCategory? sectionCategory;
  final List<MarketplaceReportMetric> metrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final useOrdersSideBySide =
        reportType == AdminReportType.ordersTransactions ||
            sectionCategory == MarketplaceReportCategory.orders;
    if (useOrdersSideBySide &&
        (metrics.isNotEmpty || breakdowns.isNotEmpty)) {
      return MarketplaceReportOrdersSideBySide(
        orderMetrics: metrics,
        breakdowns: breakdowns,
      );
    }

    final useBiddingLayout =
        reportType == AdminReportType.bidding ||
            sectionCategory == MarketplaceReportCategory.auctions;
    if (useBiddingLayout && (metrics.isNotEmpty || breakdowns.isNotEmpty)) {
      return MarketplaceReportBiddingLayout(
        metrics: metrics,
        breakdowns: breakdowns,
      );
    }

    final useVerificationsLayout =
        reportType == AdminReportType.verifications ||
            sectionCategory == MarketplaceReportCategory.verifications;
    if (useVerificationsLayout &&
        (metrics.isNotEmpty || breakdowns.isNotEmpty)) {
      return MarketplaceReportVerificationsLayout(
        metrics: metrics,
        breakdowns: breakdowns,
      );
    }

    final useDisputesLayout =
        reportType == AdminReportType.disputes ||
            sectionCategory == MarketplaceReportCategory.disputes;
    if (useDisputesLayout && (metrics.isNotEmpty || breakdowns.isNotEmpty)) {
      return MarketplaceReportDisputesLayout(
        metrics: metrics,
        breakdowns: breakdowns,
      );
    }

    final useSecurityLayout =
        reportType == AdminReportType.security ||
            sectionCategory == MarketplaceReportCategory.security;
    if (useSecurityLayout && (metrics.isNotEmpty || breakdowns.isNotEmpty)) {
      return MarketplaceReportSecurityLayout(
        metrics: metrics,
        breakdowns: breakdowns,
      );
    }

    final groups = marketplaceReportSummaryGroups(
      reportType: reportType,
      sectionCategory: sectionCategory,
      metrics: metrics,
    );

    final visibleBreakdowns = _reportBreakdownsForDisplay(
      reportType: reportType,
      sectionCategory: sectionCategory,
      breakdowns: breakdowns,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.isNotEmpty) ...[
          _AdaptiveGroupRow(
            children: [
              for (final group in groups)
                _CompactMetricTable(
                  title: group.title,
                  metrics: group.metrics,
                ),
            ],
          ),
        ],
        for (final breakdown in visibleBreakdowns) ...[
          const SizedBox(height: 12),
          _CompactBreakdownTable(breakdown: breakdown),
        ],
      ],
    );
  }
}

/// Security: restrictions on the left; admin activity, then violation consequences on the right.
class MarketplaceReportSecurityLayout extends StatelessWidget {
  const MarketplaceReportSecurityLayout({
    super.key,
    required this.metrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> metrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.security,
      metrics: metrics,
    );

    List<MarketplaceReportMetric>? restrictionsMetrics;
    List<MarketplaceReportMetric>? adminMetrics;
    for (final group in groups) {
      if (group.title == 'Security & restrictions') {
        restrictionsMetrics = group.metrics;
      } else if (group.title == 'Administrative activity') {
        adminMetrics = group.metrics;
      }
    }

    MarketplaceReportBreakdown? violationConsequences;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('violation consequence')) {
        violationConsequences = b;
        break;
      }
    }
    violationConsequences ??=
        breakdowns.isNotEmpty ? breakdowns.first : null;

    final restrictionsTable =
        restrictionsMetrics != null && restrictionsMetrics.isNotEmpty
            ? _CompactMetricTable(
                title: 'Security & restrictions',
                metrics: restrictionsMetrics,
              )
            : null;

    final adminTable = adminMetrics != null && adminMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Administrative activity',
            metrics: adminMetrics,
          )
        : null;

    final consequencesTable = violationConsequences != null
        ? _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Violation consequences (period)',
              columns: violationConsequences.columns,
              rows: violationConsequences.rows,
            ),
          )
        : null;

    if (restrictionsTable == null &&
        adminTable == null &&
        consequencesTable == null) {
      return const SizedBox.shrink();
    }

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adminTable != null) adminTable,
        if (adminTable != null && consequencesTable != null)
          const SizedBox(height: 12),
        if (consequencesTable != null) consequencesTable,
      ],
    );

    final width = MediaQuery.sizeOf(context).width;
    final useWideLayout = width >= 880 &&
        restrictionsTable != null &&
        (adminTable != null || consequencesTable != null);

    if (!useWideLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (restrictionsTable != null) restrictionsTable,
          if (restrictionsTable != null && adminTable != null)
            const SizedBox(height: 12),
          if (adminTable != null) adminTable,
          if ((restrictionsTable != null || adminTable != null) &&
              consequencesTable != null)
            const SizedBox(height: 12),
          if (consequencesTable != null) consequencesTable,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: restrictionsTable),
        const SizedBox(width: 12),
        Expanded(child: rightColumn),
      ],
    );
  }
}

/// Disputes: overview, then reports by type; outcomes on the right (wide screens).
class MarketplaceReportDisputesLayout extends StatelessWidget {
  const MarketplaceReportDisputesLayout({
    super.key,
    required this.metrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> metrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.disputes,
      metrics: metrics,
    );

    List<MarketplaceReportMetric>? overviewMetrics;
    List<MarketplaceReportMetric>? outcomesMetrics;
    for (final group in groups) {
      if (group.title == 'Dispute overview') {
        overviewMetrics = group.metrics;
      } else if (group.title == 'Outcomes & resolution') {
        outcomesMetrics = group.metrics;
      }
    }

    MarketplaceReportBreakdown? reportsByType;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('type')) {
        reportsByType = b;
        break;
      }
    }
    reportsByType ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    final overviewTable = overviewMetrics != null && overviewMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Dispute overview',
            metrics: overviewMetrics,
          )
        : null;

    final byTypeTable = reportsByType != null
        ? _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Reports by type',
              columns: reportsByType.columns,
              rows: reportsByType.rows,
            ),
          )
        : null;

    final outcomesTable = outcomesMetrics != null && outcomesMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Outcomes & resolution',
            metrics: outcomesMetrics,
          )
        : null;

    if (overviewTable == null &&
        byTypeTable == null &&
        outcomesTable == null) {
      return const SizedBox.shrink();
    }

    final overviewStack = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overviewTable != null) overviewTable,
        if (overviewTable != null && byTypeTable != null) const SizedBox(height: 12),
        if (byTypeTable != null) byTypeTable,
      ],
    );

    final width = MediaQuery.sizeOf(context).width;
    final useWideLayout = width >= 880 &&
        overviewStack.children.isNotEmpty &&
        outcomesTable != null;

    if (useWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: overviewStack),
          const SizedBox(width: 12),
          Expanded(child: outcomesTable),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overviewTable != null) overviewTable,
        if (overviewTable != null && byTypeTable != null) const SizedBox(height: 12),
        if (byTypeTable != null) byTypeTable,
        if ((overviewTable != null || byTypeTable != null) && outcomesTable != null)
          const SizedBox(height: 12),
        if (outcomesTable != null) outcomesTable,
      ],
    );
  }
}

/// Order performance metrics and status breakdown side-by-side for Orders reports.
class MarketplaceReportOrdersSideBySide extends StatelessWidget {
  const MarketplaceReportOrdersSideBySide({
    super.key,
    required this.orderMetrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> orderMetrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.ordersTransactions,
      metrics: orderMetrics,
    );
    final performanceGroup = groups
        .where((g) => g.title == 'Order performance')
        .map((g) => g.metrics)
        .firstOrNull;
    final metrics = performanceGroup ?? orderMetrics;

    MarketplaceReportBreakdown? statusTable;
    for (final b in breakdowns) {
      final title = b.title.toLowerCase();
      if (title.contains('order') && title.contains('status')) {
        statusTable = b;
        break;
      }
    }
    statusTable ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    if (metrics.isEmpty && statusTable == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.isNotEmpty)
          _CompactMetricTable(
            title: 'Order performance',
            metrics: metrics,
          ),
        if (metrics.isNotEmpty && statusTable != null) const SizedBox(height: 12),
        if (statusTable != null)
          _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Orders by status',
              columns: statusTable.columns,
              rows: statusTable.rows,
            ),
          ),
      ],
    );
  }
}

/// Orders & Transactions report: 2×2 grid (orders left, payments right).
class MarketplaceReportOrdersTransactionsGrid extends StatelessWidget {
  const MarketplaceReportOrdersTransactionsGrid({
    super.key,
    required this.orderMetrics,
    required this.orderBreakdowns,
    required this.paymentMetrics,
    required this.paymentBreakdowns,
  });

  final List<MarketplaceReportMetric> orderMetrics;
  final List<MarketplaceReportBreakdown> orderBreakdowns;
  final List<MarketplaceReportMetric> paymentMetrics;
  final List<MarketplaceReportBreakdown> paymentBreakdowns;

  @override
  Widget build(BuildContext context) {
    final ordersColumn = MarketplaceReportOrdersSideBySide(
      orderMetrics: orderMetrics,
      breakdowns: orderBreakdowns,
    );
    final paymentsColumn = _PaymentsSummaryColumn(
      paymentMetrics: paymentMetrics,
      breakdowns: paymentBreakdowns,
    );

    final hasOrders = orderMetrics.isNotEmpty || orderBreakdowns.isNotEmpty;
    final hasPayments =
        paymentMetrics.isNotEmpty || paymentBreakdowns.isNotEmpty;

    if (!hasOrders && !hasPayments) {
      return const SizedBox.shrink();
    }
    if (!hasPayments) return ordersColumn;
    if (!hasOrders) return paymentsColumn;

    final width = MediaQuery.sizeOf(context).width;
    if (width < 880) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ordersColumn,
          const SizedBox(height: 16),
          paymentsColumn,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: ordersColumn),
        const SizedBox(width: 12),
        Expanded(child: paymentsColumn),
      ],
    );
  }
}

class _PaymentsSummaryColumn extends StatelessWidget {
  const _PaymentsSummaryColumn({
    required this.paymentMetrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> paymentMetrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.ordersTransactions,
      metrics: paymentMetrics,
    );
    final paymentsGroup = groups
        .where((g) => g.title == 'Payments & revenue')
        .map((g) => g.metrics)
        .firstOrNull;
    final metrics = paymentsGroup ?? paymentMetrics;

    MarketplaceReportBreakdown? statusTable;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('payment status')) {
        statusTable = b;
        break;
      }
    }
    statusTable ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    if (metrics.isEmpty && statusTable == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.isNotEmpty)
          _CompactMetricTable(
            title: 'Transactions & payments',
            metrics: metrics,
          ),
        if (metrics.isNotEmpty && statusTable != null) const SizedBox(height: 12),
        if (statusTable != null)
          _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Payment status',
              columns: statusTable.columns,
              rows: statusTable.rows,
            ),
          ),
      ],
    );
  }
}

/// Seller verification: left — summary; right — processing performance + outcomes.
class MarketplaceReportVerificationsLayout extends StatelessWidget {
  const MarketplaceReportVerificationsLayout({
    super.key,
    required this.metrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> metrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.verifications,
      metrics: metrics,
    );

    List<MarketplaceReportMetric>? summaryMetrics;
    List<MarketplaceReportMetric>? performanceMetrics;
    for (final group in groups) {
      if (group.title == 'Verification summary') {
        summaryMetrics = group.metrics;
      } else if (group.title == 'Processing performance') {
        performanceMetrics = group.metrics;
      }
    }

    MarketplaceReportBreakdown? outcomesTable;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('outcome')) {
        outcomesTable = b;
        break;
      }
    }
    outcomesTable ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    final summaryTable = summaryMetrics != null && summaryMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Verification summary',
            metrics: summaryMetrics,
          )
        : null;

    final performanceTable =
        performanceMetrics != null && performanceMetrics.isNotEmpty
            ? _CompactMetricTable(
                title: 'Processing performance',
                metrics: performanceMetrics,
              )
            : null;

    final outcomesBreakdown = outcomesTable != null
        ? _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Outcomes',
              columns: outcomesTable.columns,
              rows: outcomesTable.rows,
            ),
          )
        : null;

    if (summaryTable == null &&
        performanceTable == null &&
        outcomesBreakdown == null) {
      return const SizedBox.shrink();
    }

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (performanceTable != null) performanceTable,
        if (performanceTable != null && outcomesBreakdown != null)
          const SizedBox(height: 12),
        if (outcomesBreakdown != null) outcomesBreakdown,
      ],
    );

    final width = MediaQuery.sizeOf(context).width;
    final useWideLayout = width >= 880 &&
        summaryTable != null &&
        (performanceTable != null || outcomesBreakdown != null);

    if (!useWideLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summaryTable != null) summaryTable,
          if (summaryTable != null && performanceTable != null)
            const SizedBox(height: 12),
          if (performanceTable != null) performanceTable,
          if ((summaryTable != null || performanceTable != null) &&
              outcomesBreakdown != null)
            const SizedBox(height: 12),
          if (outcomesBreakdown != null) outcomesBreakdown,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: summaryTable),
        const SizedBox(width: 12),
        Expanded(child: rightColumn),
      ],
    );
  }
}

/// Bidding reports: left — auction performance; right — status, then activity.
class MarketplaceReportBiddingLayout extends StatelessWidget {
  const MarketplaceReportBiddingLayout({
    super.key,
    required this.metrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> metrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.bidding,
      metrics: metrics,
    );

    List<MarketplaceReportMetric> performanceMetrics = metrics;
    List<MarketplaceReportMetric>? activityMetrics;
    for (final group in groups) {
      if (group.title == 'Auction performance') {
        performanceMetrics = group.metrics;
      } else if (group.title == 'Bidding activity') {
        activityMetrics = group.metrics;
      }
    }

    MarketplaceReportBreakdown? statusTable;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('auction status')) {
        statusTable = b;
        break;
      }
    }
    statusTable ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    final activityTable = activityMetrics != null && activityMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Bidding activity',
            metrics: activityMetrics,
          )
        : null;

    final statusBreakdown = statusTable != null
        ? _CompactBreakdownTable(
            breakdown: MarketplaceReportBreakdown(
              title: 'Auction status',
              columns: statusTable.columns,
              rows: statusTable.rows,
            ),
          )
        : null;

    final performanceTable = performanceMetrics.isNotEmpty
        ? _CompactMetricTable(
            title: 'Auction performance',
            metrics: performanceMetrics,
          )
        : null;

    if (activityTable == null &&
        statusBreakdown == null &&
        performanceTable == null) {
      return const SizedBox.shrink();
    }

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (statusBreakdown != null) statusBreakdown,
        if (statusBreakdown != null && activityTable != null)
          const SizedBox(height: 12),
        if (activityTable != null) activityTable,
      ],
    );

    final width = MediaQuery.sizeOf(context).width;
    final useWideLayout = width >= 880 &&
        performanceTable != null &&
        rightColumn.children.isNotEmpty;

    if (useWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: performanceTable!),
          const SizedBox(width: 12),
          Expanded(child: rightColumn),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (performanceTable != null) performanceTable,
        if (performanceTable != null && statusBreakdown != null)
          const SizedBox(height: 12),
        if (statusBreakdown != null) statusBreakdown,
        if ((performanceTable != null || statusBreakdown != null) &&
            activityTable != null)
          const SizedBox(height: 12),
        if (activityTable != null) activityTable,
      ],
    );
  }
}

/// Side-by-side payments summary and payment-status breakdown for Orders & Transactions.
class MarketplaceReportPaymentsSideBySide extends StatelessWidget {
  const MarketplaceReportPaymentsSideBySide({
    super.key,
    required this.paymentMetrics,
    required this.breakdowns,
  });

  final List<MarketplaceReportMetric> paymentMetrics;
  final List<MarketplaceReportBreakdown> breakdowns;

  @override
  Widget build(BuildContext context) {
    final groups = marketplaceReportSummaryGroups(
      reportType: AdminReportType.ordersTransactions,
      metrics: paymentMetrics,
    );
    final paymentsGroup = groups
        .where((g) => g.title == 'Payments & revenue')
        .map((g) => g.metrics)
        .firstOrNull;
    final metrics = paymentsGroup ?? paymentMetrics;

    MarketplaceReportBreakdown? statusTable;
    for (final b in breakdowns) {
      if (b.title.toLowerCase().contains('payment status')) {
        statusTable = b;
        break;
      }
    }
    statusTable ??= breakdowns.isNotEmpty ? breakdowns.first : null;

    if (metrics.isEmpty && statusTable == null) {
      return const SizedBox.shrink();
    }

    return _PaymentsSummaryColumn(
      paymentMetrics: paymentMetrics,
      breakdowns: breakdowns,
    );
  }
}

class MarketplaceReportOverviewGrid extends StatelessWidget {
  const MarketplaceReportOverviewGrid({
    super.key,
    required this.metrics,
  });

  final List<MarketplaceReportMetric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarketplaceReportSummaryLayout(
      reportType: AdminReportType.all,
      metrics: metrics,
    );
  }
}

class _AdaptiveGroupRow extends StatelessWidget {
  const _AdaptiveGroupRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRow = width >= 880 && children.length > 1;

    if (!useRow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _CompactMetricTable extends StatelessWidget {
  const _CompactMetricTable({
    required this.title,
    required this.metrics,
  });

  final String title;
  final List<MarketplaceReportMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.tableBodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          AdminDataTable(
            minWidth: 260,
            columns: const ['Metric', 'Value'],
            columnFlex: const [3, 2],
            columnAlignments: const [
              Alignment.centerLeft,
              Alignment.centerRight,
            ],
            rows: metrics
                .map(
                  (m) => [
                    AdminTableCellText(
                      primary: m.snapshot ? '${m.label} (snapshot)' : m.label,
                    ),
                    AdminTableCellText(primary: m.display),
                  ],
                )
                .toList(),
            emptyTitle: 'No metrics',
            emptyMessage: 'No data for this group.',
          ),
        ],
      ),
    );
  }
}

class _CompactBreakdownTable extends StatelessWidget {
  const _CompactBreakdownTable({required this.breakdown});

  final MarketplaceReportBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final compact = breakdown.rows.length <= 6 && breakdown.columns.length <= 3;

    return Container(
      width: compact ? null : double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            breakdown.title,
            style: AppTypography.tableBodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AdminDataTable(
            minWidth: compact ? 280 : 520,
            columns: breakdown.columns,
            columnFlex: breakdown.columns.length == 2 ? const [2, 1] : null,
            columnAlignments: breakdown.columns.length == 2
                ? const [Alignment.centerLeft, Alignment.centerRight]
                : null,
            rows: breakdown.rows
                .map((row) => row.map((c) => AdminTableCellText(primary: c)).toList())
                .toList(),
            emptyTitle: 'No breakdown',
            emptyMessage: 'No rows for this period.',
          ),
        ],
      ),
    );
  }
}
