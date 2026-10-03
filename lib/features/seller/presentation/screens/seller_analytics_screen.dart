import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../controllers/seller_analytics_controller.dart';
import '../../data/seller_analytics.dart';
import '../../data/seller_analytics_comparison.dart';
import '../../data/seller_analytics_period.dart';
import '../widgets/seller_analytics_widgets.dart';

class SellerAnalyticsScreen extends StatelessWidget {
  const SellerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SellerAnalyticsController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics Report'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: ctrl.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMd,
            AppConstants.spacingMd,
            AppConstants.spacingMd,
            32,
          ),
          children: [
            _FilterBar(controller: ctrl),
            if (ctrl.validationMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                ctrl.validationMessage!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 16),
            if (ctrl.isLoading && ctrl.report == null)
              const _AnalyticsSkeleton()
            else if (ctrl.errorMessage != null && ctrl.report == null)
              _ErrorState(onRetry: ctrl.refresh)
            else if (ctrl.report != null)
              _AnalyticsBody(
                report: ctrl.report!,
                window: ctrl.window,
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final SellerAnalyticsController controller;

  static const _presets = <(SellerAnalyticsPreset, String)>[
    (SellerAnalyticsPreset.allTime, 'All Time'),
    (SellerAnalyticsPreset.today, 'Today'),
    (SellerAnalyticsPreset.last7Days, 'Last 7 Days'),
    (SellerAnalyticsPreset.lastMonth, 'Last Month'),
    (SellerAnalyticsPreset.lastYear, 'Last Year'),
    (SellerAnalyticsPreset.custom, 'Custom'),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = controller.preset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (preset, label) = _presets[i];
              final isSelected = selected == preset;
              return FilterChip(
                label: Text(label),
                selected: isSelected,
                showCheckmark: false,
                labelStyle: AppTypography.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
                onSelected: (_) async {
                  if (preset == SellerAnalyticsPreset.custom) {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: controller.customStart != null &&
                              controller.customEnd != null
                          ? DateTimeRange(
                              start: controller.customStart!,
                              end: controller.customEnd!,
                            )
                          : DateTimeRange(
                              start: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              end: DateTime.now(),
                            ),
                    );
                    if (range != null && context.mounted) {
                      await controller.applyCustomRange(
                        range.start,
                        range.end,
                      );
                    }
                    return;
                  }
                  await controller.selectPreset(preset);
                },
              );
            },
          ),
        ),
        if (controller.window != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.window!.periodLabel,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({
    required this.report,
    required this.window,
  });

  final SellerAnalyticsReport report;
  final SellerAnalyticsPeriodWindow? window;

  @override
  Widget build(BuildContext context) {
    final vsLabel = window?.vsPreviousLabel ?? '';
    final periodLabel = window?.periodLabel ?? '';
    final includeCompare = report.includeComparison;

    final incomeComparison = SellerAnalyticsComparison.fromCentavos(
      current: report.earningsCentavos,
      previous: report.previousEarningsCentavos,
      includeComparison: includeCompare,
    );
    final productsComparison = SellerAnalyticsComparison.fromValues(
      current: report.productsSold,
      previous: report.previousProductsSold,
      includeComparison: includeCompare,
    );

    final hasData = report.earningsCentavos > 0 ||
        report.productsSold > 0 ||
        report.completedOrders > 0;

    final avgPerOrder = report.completedOrders > 0
        ? report.earningsCentavos ~/ report.completedOrders
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasData) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No analytics yet',
                  style: AppTypography.subheading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your shop analytics will appear here as your listings '
                  'receive activity and orders.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        const AnalyticsSectionTitle(
          title: 'Performance overview',
          subtitle: 'Released income and completed orders for this period',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 340;
            if (narrow) {
              return Column(
                children: [
                  _overviewCard(
                    label: 'Total income',
                    value: formatCentavos(report.earningsCentavos),
                    comparison: incomeComparison,
                    vsLabel: vsLabel,
                    emphasize: true,
                  ),
                  const SizedBox(height: 12),
                  _overviewCard(
                    label: 'Products sold',
                    value: '${report.productsSold}',
                    comparison: productsComparison,
                    vsLabel: vsLabel,
                  ),
                  const SizedBox(height: 12),
                  _overviewCard(
                    label: 'Completed orders',
                    value: '${report.completedOrders}',
                    comparison: null,
                    vsLabel: '',
                  ),
                  const SizedBox(height: 12),
                  _overviewCard(
                    label: 'Avg. per order',
                    value: avgPerOrder != null
                        ? formatCentavos(avgPerOrder)
                        : '—',
                    comparison: null,
                    vsLabel: '',
                  ),
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _overviewCard(
                        label: 'Total income',
                        value: formatCentavos(report.earningsCentavos),
                        comparison: incomeComparison,
                        vsLabel: vsLabel,
                        emphasize: true,
                        valueColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _overviewCard(
                        label: 'Products sold',
                        value: '${report.productsSold}',
                        comparison: productsComparison,
                        vsLabel: vsLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _overviewCard(
                        label: 'Completed orders',
                        value: '${report.completedOrders}',
                        comparison: null,
                        vsLabel: '',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _overviewCard(
                        label: 'Avg. per order',
                        value: avgPerOrder != null
                            ? formatCentavos(avgPerOrder)
                            : '—',
                        comparison: null,
                        vsLabel: '',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Income counts money released to your shop. Held or refunded amounts are excluded.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textHint,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 28),
        AnalyticsSectionTitle(
          title: 'Sales trend',
          subtitle: periodLabel.isNotEmpty ? periodLabel : null,
        ),
        const SizedBox(height: 12),
        if (report.chart.isEmpty)
          AnalyticsEmptyChartPlaceholder(
            message: hasData
                ? 'Not enough data points for a chart in this period.'
                : 'No income trend to show for this period yet.',
          )
        else
          AnalyticsEarningsChart(
            points: report.chart,
            periodCaption: periodLabel,
          ),
        if (includeCompare && window != null && window!.preset != SellerAnalyticsPreset.allTime) ...[
          const SizedBox(height: 28),
          AnalyticsComparisonBars(
            sectionTitle: window!.currentPeriodComparisonTitle,
            rows: [
              AnalyticsComparisonBarRow(
                metricLabel: 'Total income',
                currentLabel: window!.periodLabel,
                previousLabel: _previousBarLabel(window!),
                currentValue: report.earningsCentavos,
                previousValue: report.previousEarningsCentavos,
                formatValue: (v) => formatCentavos(v.round()),
              ),
              AnalyticsComparisonBarRow(
                metricLabel: 'Products sold',
                currentLabel: window!.periodLabel,
                previousLabel: _previousBarLabel(window!),
                currentValue: report.productsSold,
                previousValue: report.previousProductsSold,
                formatValue: (v) => v.round().toString(),
              ),
            ],
          ),
          if (incomeComparison.noPreviousPeriodData &&
              productsComparison.noPreviousPeriodData) ...[
            const SizedBox(height: 8),
            Text(
              'No previous-period data available for comparison.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
        if (report.recentSales.isNotEmpty) ...[
          const SizedBox(height: 28),
          const AnalyticsSectionTitle(
            title: 'Recent sales',
            subtitle: 'Latest released payouts in this period',
          ),
          const SizedBox(height: 12),
          ...report.recentSales.map(
            (sale) => AnalyticsRecentSaleTile(sale: sale),
          ),
        ],
      ],
    );
  }

  Widget _overviewCard({
    required String label,
    required String value,
    required SellerAnalyticsComparison? comparison,
    required String vsLabel,
    bool emphasize = false,
    Color? valueColor,
  }) {
    return AnalyticsMetricCard(
      label: label,
      value: value,
      comparison: comparison,
      vsLabel: vsLabel,
      emphasizeValue: emphasize,
      valueColor: valueColor,
    );
  }

  static String _previousBarLabel(SellerAnalyticsPeriodWindow window) {
    return switch (window.preset) {
      SellerAnalyticsPreset.today => 'Yesterday',
      SellerAnalyticsPreset.last7Days => 'Previous 7 days',
      SellerAnalyticsPreset.lastMonth => 'Month before',
      SellerAnalyticsPreset.lastYear => 'Previous year',
      SellerAnalyticsPreset.custom => 'Previous period',
      SellerAnalyticsPreset.allTime => 'Previous',
    };
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 180, height: 14),
        SizedBox(height: 12),
        AnalyticsOverviewSkeleton(),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.textHint.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            context.watch<SellerAnalyticsController>().errorMessage ??
                'Unable to load analytics. Please try again.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
