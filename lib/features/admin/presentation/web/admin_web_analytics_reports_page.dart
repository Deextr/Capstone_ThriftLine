import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../controllers/admin_analytics_controller.dart';
import '../../data/admin_dashboard_models.dart';
import '../widgets/admin_dashboard_widgets.dart';
import '../widgets/admin_ui_components.dart';

final _percentFormat = NumberFormat('#,##0.0');

class AdminWebAnalyticsReportsPage extends StatelessWidget {
  const AdminWebAnalyticsReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminAnalyticsController>();
    final snapshot = controller.snapshot;
    final previous = controller.previousSnapshot;
    final comparison = controller.comparison;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AdminPageHeader(
            title: 'Reports',
            subtitle:
                'Analytical view of marketplace performance, user growth, and ThriftLine platform-fee revenue (not gross marketplace sales).',
            actions: [
              OutlinedButton.icon(
                onPressed: controller.isLoading
                    ? null
                    : () => controller.load(),
                icon: Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          AdminDashboardDateRangeBar(
            window: controller.window,
            onPresetSelected: (preset) async {
              if (preset == AdminDatePreset.custom) return;
              final window = switch (preset) {
                AdminDatePreset.today => AdminDateWindow.today(),
                AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
                AdminDatePreset.last30Days => AdminDateWindow.last30Days(),
                AdminDatePreset.thisMonth => AdminDateWindow.thisMonth(),
                AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
                AdminDatePreset.custom => AdminDateWindow.last30Days(),
              };
              controller.setWindow(window);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Compare to previous period',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Shows change vs the immediately preceding range of equal length.',
              style: AppTypography.caption,
            ),
            value: controller.comparePrevious,
            activeThumbColor: AppColors.primary,
            onChanged: controller.isLoading
                ? null
                : controller.setComparePrevious,
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.errorMessage!,
              style: AppTypography.body.copyWith(color: AppColors.error),
            ),
          ],
          if (controller.isLoading && snapshot == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (snapshot != null) ...[
            const SizedBox(height: 24),
            _ReportSection(
              title: 'User growth',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetricComparisonRow(
                    label: 'New registrations',
                    current: snapshot.counts.registeredInPeriod,
                    previous: previous?.counts.registeredInPeriod,
                    percent: comparison?.percentChange(
                      snapshot.counts.registeredInPeriod,
                      previous?.counts.registeredInPeriod,
                    ),
                  ),
                  _MetricComparisonRow(
                    label: 'Total registered users',
                    current: snapshot.counts.totalUsers,
                    previous: null,
                    percent: null,
                    isCurrency: false,
                    showComparison: false,
                  ),
                  const SizedBox(height: 16),
                  AdminTrendChart(
                    title: 'Registration trend',
                    points: snapshot.registrations,
                    emptyMessage: 'No new registrations in this period.',
                  ),
                  const SizedBox(height: 16),
                  _BreakdownTable(
                    title: 'Daily registrations',
                    headers: const ['Period', 'New users'],
                    rows: [
                      for (final point in snapshot.registrations)
                        [formatFullDate(point.day), '${point.count}'],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ReportSection(
              title: 'Marketplace performance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetricComparisonRow(
                    label: 'Orders placed',
                    current: snapshot.counts.ordersPlaced,
                    previous: previous?.counts.ordersPlaced,
                    percent: comparison?.percentChange(
                      snapshot.counts.ordersPlaced,
                      previous?.counts.ordersPlaced,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AdminTrendChart(
                    title: 'Order volume',
                    points: snapshot.ordersByDay,
                    emptyMessage: 'No orders in this period.',
                    breakdown: snapshot.ordersByStatus,
                    breakdownLabel: (status) =>
                        orderStatusLabel(orderStatusFromDb(status)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ReportSection(
              title: 'Platform revenue',
              subtitle:
                  'Gross marketplace value (buyer-paid subtotal + shipping on paid orders) is separate from ThriftLine platform-fee revenue.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetricComparisonRow(
                    label: 'Gross marketplace value (paid orders)',
                    current: snapshot.counts.grossMarketplaceSales.round(),
                    previous: previous?.counts.grossMarketplaceSales.round(),
                    percent: comparison?.percentChange(
                      snapshot.counts.grossMarketplaceSales,
                      previous?.counts.grossMarketplaceSales,
                    ),
                    isCurrency: true,
                  ),
                  _MetricComparisonRow(
                    label: 'ThriftLine platform-fee revenue',
                    current: snapshot.counts.platformRevenue.round(),
                    previous: previous?.counts.platformRevenue.round(),
                    percent: comparison?.percentChange(
                      snapshot.counts.platformRevenue,
                      previous?.counts.platformRevenue,
                    ),
                    isCurrency: true,
                  ),
                  const SizedBox(height: 16),
                  AdminTrendChart(
                    title: 'Paid sales vs platform fees',
                    points: [
                      for (final point in snapshot.salesRevenueSeries)
                        AdminDashboardPoint(
                          day: point.day,
                          count: point.platformRevenue.round(),
                        ),
                    ],
                    emptyMessage: 'No paid orders in this period.',
                  ),
                  const SizedBox(height: 16),
                  _BreakdownTable(
                    title: 'Revenue breakdown by period bucket',
                    headers: const ['Period', 'GMV (paid)', 'Platform fee'],
                    rows: [
                      for (final point in snapshot.salesRevenueSeries)
                        [
                          formatFullDate(point.day),
                          formatCurrency(point.gross),
                          formatCurrency(point.platformRevenue),
                        ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ReportSection(
              title: 'Trust & safety activity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetricComparisonRow(
                    label: 'Reports submitted',
                    current: snapshot.counts.reportsSubmitted,
                    previous: previous?.counts.reportsSubmitted,
                    percent: comparison?.percentChange(
                      snapshot.counts.reportsSubmitted,
                      previous?.counts.reportsSubmitted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AdminTrendChart(
                    title: 'Report volume',
                    points: snapshot.reportsByDay,
                    emptyMessage: 'No reports in this period.',
                    breakdown: snapshot.reportsByStatus,
                    breakdownLabel: (status) => status.replaceAll('_', ' '),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTypography.label.copyWith(
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 6),
          Text(subtitle!, style: AppTypography.caption.copyWith(height: 1.4)),
        ],
        const SizedBox(height: 16),
        child,
        Divider(height: 48, color: AppColors.border),
      ],
    );
  }
}

class _MetricComparisonRow extends StatelessWidget {
  const _MetricComparisonRow({
    required this.label,
    required this.current,
    this.previous,
    this.percent,
    this.isCurrency = false,
    this.showComparison = true,
  });

  final String label;
  final int current;
  final int? previous;
  final double? percent;
  final bool isCurrency;
  final bool showComparison;

  @override
  Widget build(BuildContext context) {
    final currentLabel = isCurrency
        ? formatCurrency(current.toDouble())
        : NumberFormat.decimalPattern().format(current);
    String? changeLabel;
    if (showComparison && previous != null && percent != null) {
      final sign = percent! >= 0 ? '+' : '';
      changeLabel = '$sign${_percentFormat.format(percent)}% vs prior period';
    } else if (showComparison && previous != null && percent == null) {
      changeLabel = 'No prior-period baseline';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTypography.body)),
          Expanded(
            child: Text(
              currentLabel,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ),
          if (changeLabel != null)
            Expanded(
              child: Text(
                changeLabel,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownTable extends StatelessWidget {
  const _BreakdownTable({
    required this.title,
    required this.headers,
    required this.rows,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.subheading),
        const SizedBox(height: 8),
        AdminDataTable(
          columns: headers,
          rows: [
            for (final row in rows)
              [
                for (final cell in row)
                  Text(cell, style: AppTypography.caption),
              ],
          ],
          minWidth: 480,
        ),
      ],
    );
  }
}
