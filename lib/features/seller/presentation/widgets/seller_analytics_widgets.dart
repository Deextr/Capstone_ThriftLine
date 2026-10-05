import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/seller_analytics.dart';
import '../../data/seller_analytics_comparison.dart';

/// Shared metric card height for overview grid alignment.
const double kAnalyticsMetricCardMinHeight = 118;

class AnalyticsSectionTitle extends StatelessWidget {
  const AnalyticsSectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class AnalyticsMetricCard extends StatelessWidget {
  const AnalyticsMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.comparison,
    this.vsLabel = '',
    this.emphasizeValue = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final SellerAnalyticsComparison? comparison;
  final String vsLabel;
  final bool emphasizeValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: kAnalyticsMetricCardMinHeight,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style:
                  (emphasizeValue
                          ? AppTypography.heading.copyWith(fontSize: 24)
                          : AppTypography.heading.copyWith(fontSize: 22))
                      .copyWith(
                        fontWeight: FontWeight.w800,
                        color: valueColor ?? AppColors.textPrimary,
                      ),
            ),
          ),
          const SizedBox(height: 6),
          AnalyticsTrendRow(comparison: comparison, vsLabel: vsLabel),
        ],
      ),
    );
  }
}

class AnalyticsTrendRow extends StatelessWidget {
  const AnalyticsTrendRow({
    super.key,
    required this.comparison,
    this.vsLabel = '',
  });

  final SellerAnalyticsComparison? comparison;
  final String vsLabel;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    if (c == null || !c.hasComparison) {
      return const SizedBox(height: 18);
    }

    if (c.noPreviousPeriodData) {
      return Text(
        'No previous-period data',
        style: AppTypography.caption.copyWith(
          color: AppColors.textHint,
          fontSize: 11,
          height: 1.2,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final trend = c.shortTrendText;
    if (trend == null) {
      return const SizedBox(height: 18);
    }

    final isUp = c.percentChange != null && c.percentChange! > 0;
    final isDown = c.percentChange != null && c.percentChange! < 0;
    final trendColor = isUp
        ? AppColors.success
        : isDown
        ? AppColors.error
        : AppColors.textSecondary;

    return Row(
      children: [
        Icon(
          isUp
              ? Icons.arrow_upward_rounded
              : isDown
              ? Icons.arrow_downward_rounded
              : Icons.remove_rounded,
          size: 14,
          color: trendColor,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            [trend, if (vsLabel.isNotEmpty) vsLabel].join(' '),
            style: AppTypography.caption.copyWith(
              color: trendColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class AnalyticsComparisonBars extends StatelessWidget {
  const AnalyticsComparisonBars({
    super.key,
    required this.sectionTitle,
    required this.rows,
  });

  final String sectionTitle;
  final List<AnalyticsComparisonBarRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyticsSectionTitle(title: sectionTitle),
        const SizedBox(height: 12),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ComparisonBarRow(data: row),
          ),
        ),
      ],
    );
  }
}

class AnalyticsComparisonBarRow {
  const AnalyticsComparisonBarRow({
    required this.metricLabel,
    required this.currentLabel,
    required this.previousLabel,
    required this.currentValue,
    required this.previousValue,
    required this.formatValue,
  });

  final String metricLabel;
  final String currentLabel;
  final String previousLabel;
  final num currentValue;
  final num previousValue;
  final String Function(num value) formatValue;
}

class _ComparisonBarRow extends StatelessWidget {
  const _ComparisonBarRow({required this.data});

  final AnalyticsComparisonBarRow data;

  @override
  Widget build(BuildContext context) {
    final maxVal = [
      data.currentValue,
      data.previousValue,
    ].fold<num>(0, (a, b) => a > b ? a : b);
    final scale = maxVal <= 0 ? 1.0 : maxVal.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.metricLabel,
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        _BarLine(
          label: data.currentLabel,
          valueText: data.formatValue(data.currentValue),
          fraction: maxVal <= 0 ? 0 : data.currentValue / scale,
          barColor: AppColors.primary,
        ),
        const SizedBox(height: 6),
        _BarLine(
          label: data.previousLabel,
          valueText: data.formatValue(data.previousValue),
          fraction: maxVal <= 0 ? 0 : data.previousValue / scale,
          barColor: AppColors.textHint.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.barColor,
  });

  final String label;
  final String valueText;
  final double fraction;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth * fraction.clamp(0.0, 1.0);
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.border.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (w > 0)
                    Container(
                      width: w,
                      height: 8,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            valueText,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class AnalyticsEarningsChart extends StatelessWidget {
  const AnalyticsEarningsChart({
    super.key,
    required this.points,
    required this.periodCaption,
  });

  final List<SellerAnalyticsChartPoint> points;
  final String periodCaption;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].earningsCentavos / 100));
    }
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final top = maxY <= 0 ? 100.0 : maxY * 1.15;
    final showDots = spots.length <= 14;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Released income in this period (₱)',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (periodCaption.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              periodCaption,
              style: AppTypography.caption.copyWith(
                color: AppColors.textHint,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: top,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: top / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.35),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: top / 4,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > top) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _compactPeso(value),
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.textHint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: spots.length <= 8,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final d = points[i].bucketStart;
                        if (d == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _bucketLabel(d),
                            style: AppTypography.caption.copyWith(
                              fontSize: 9,
                              color: AppColors.textHint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) {
                      return touched.map((t) {
                        final i = t.spotIndex;
                        if (i < 0 || i >= points.length) return null;
                        return LineTooltipItem(
                          formatCentavos(points[i].earningsCentavos),
                          AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: spots.length > 2,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(show: showDots),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _compactPeso(double pesos) {
    if (pesos >= 1000000) {
      return '₱${(pesos / 1000000).toStringAsFixed(1)}M';
    }
    if (pesos >= 1000) {
      return '₱${(pesos / 1000).toStringAsFixed(0)}k';
    }
    return '₱${pesos.round()}';
  }

  static String _bucketLabel(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class AnalyticsRecentSaleTile extends StatelessWidget {
  const AnalyticsRecentSaleTile({super.key, required this.sale});

  final SellerAnalyticsRecentSale sale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.sell_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (sale.orderNumber.isNotEmpty) '#${sale.orderNumber}',
                    if (sale.releasedAt != null)
                      _formatSaleDate(sale.releasedAt!),
                  ].where((s) => s.isNotEmpty).join(' • '),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatCentavos(sale.sellerAmountCentavos),
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSaleDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class AnalyticsEmptyChartPlaceholder extends StatelessWidget {
  const AnalyticsEmptyChartPlaceholder({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 32,
            color: AppColors.textHint.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class AnalyticsOverviewSkeleton extends StatelessWidget {
  const AnalyticsOverviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _metricSkeleton()),
            const SizedBox(width: 12),
            Expanded(child: _metricSkeleton()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metricSkeleton()),
            const SizedBox(width: 12),
            Expanded(child: _metricSkeleton()),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  Widget _metricSkeleton() {
    return Container(
      height: kAnalyticsMetricCardMinHeight,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
