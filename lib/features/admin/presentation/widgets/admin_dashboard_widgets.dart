import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_dashboard_models.dart';
import 'admin_review_widgets.dart';

final _countFormat = NumberFormat.decimalPattern();

class AdminDashboardBanner extends StatelessWidget {
  const AdminDashboardBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          message,
          style: AppTypography.caption.copyWith(
            color: const Color(0xFF92400E),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class AdminOverviewCard extends StatelessWidget {
  const AdminOverviewCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.onTap,
    this.attention = false,
  });

  final String label;
  final int value;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;
  final bool attention;

  static const double cardHeight = 132;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: attention ? AppColors.primary : AppColors.textSecondary,
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: attention ? AppColors.primary : AppColors.textHint,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _countFormat.format(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.heading.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: '$label, ${_countFormat.format(value)}. $detail',
      child: SizedBox(
        height: cardHeight,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            side: BorderSide(
              color: attention
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: onTap == null
              ? content
              : InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class AdminOverviewCardSkeleton extends StatelessWidget {
  const AdminOverviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: AdminOverviewCard.cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(
            Radius.circular(AppConstants.radiusMd),
          ),
          border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 18, height: 18, radius: 4),
              SizedBox(height: 12),
              ShimmerBox(width: 64, height: 22),
              SizedBox(height: 8),
              ShimmerBox(width: 96, height: 12),
              SizedBox(height: 6),
              ShimmerBox(width: 120, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminDashboardFilterBar<T> extends StatelessWidget {
  const AdminDashboardFilterBar({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final value in values)
          AdminUnderlineFilter(
            label: labelOf(value),
            selected: value == selected,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }
}

Future<AdminDateWindow?> showAdminCustomRangePicker(
  BuildContext context, {
  AdminDateWindow? initial,
}) {
  var start = initial?.from ?? DateTime.now().subtract(const Duration(days: 6));
  var end = initial == null
      ? DateTime.now()
      : initial.toExclusive.subtract(const Duration(seconds: 1));
  start = DateTime(start.year, start.month, start.day);
  end = DateTime(end.year, end.month, end.day);

  return showDialog<AdminDateWindow>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pick({required bool isStart}) async {
            final picked = await showDatePicker(
              context: context,
              initialDate: isStart ? start : end,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked == null) return;
            setState(() {
              if (isStart) {
                start = DateTime(picked.year, picked.month, picked.day);
                if (end.isBefore(start)) end = start;
              } else {
                end = DateTime(picked.year, picked.month, picked.day);
                if (end.isBefore(start)) start = end;
              }
            });
          }

          return AlertDialog(
            title: const Text('Custom range'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  subtitle: Text(formatFullDate(start)),
                  trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                  onTap: () => pick(isStart: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End date'),
                  subtitle: Text(formatFullDate(end)),
                  trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                  onTap: () => pick(isStart: false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(AdminDateWindow.custom(start: start, end: end));
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
}

class AdminQuickAction extends StatelessWidget {
  const AdminQuickAction({
    super.key,
    required this.label,
    required this.onTap,
    this.count,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final suffix = (count != null && count! > 0) ? ' ($count)' : '';
    return ThriftButton(
      label: '$label$suffix',
      onPressed: onTap,
      expand: false,
      variant: primary
          ? ThriftButtonVariant.primary
          : ThriftButtonVariant.outline,
    );
  }
}

class AdminTrendChart extends StatelessWidget {
  const AdminTrendChart({
    super.key,
    required this.title,
    required this.points,
    required this.emptyMessage,
    this.breakdown = const [],
    this.breakdownLabel,
  });

  final String title;
  final List<AdminDashboardPoint> points;
  final String emptyMessage;
  final List<AdminDashboardStatusCount> breakdown;
  final String Function(String status)? breakdownLabel;

  @override
  Widget build(BuildContext context) {
    final total = points.fold<int>(0, (sum, point) => sum + point.count);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.subheading),
            const SizedBox(height: 4),
            Text(
              total == 0 ? emptyMessage : '$total in this period',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),
            if (total > 0)
              SizedBox(
                height: 160,
                width: double.infinity,
                child: _LineChart(points: points),
              ),
            if (breakdown.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final item in breakdown)
                    Text(
                      '${breakdownLabel?.call(item.status) ?? item.status} ${item.count}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points});

  final List<AdminDashboardPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<int>(0, (sum, point) {
      return point.count > sum ? point.count : sum;
    }).toDouble();
    final top = maxY <= 0 ? 1.0 : (maxY * 1.2).ceilToDouble();
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].count.toDouble()),
    ];
    final labelEvery = _labelEvery(points.length);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(1, 1000).toDouble(),
        minY: 0,
        maxY: top,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _interval(top),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
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
              reservedSize: 28,
              interval: _interval(top),
              getTitlesWidget: (value, _) {
                if (value < 0 || value > top) return const SizedBox.shrink();
                return Text(
                  value.toInt().toString(),
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                if (index % labelEvery != 0 && index != points.length - 1) {
                  return const SizedBox.shrink();
                }
                return Text(
                  DateFormat('MMM d').format(points[index].day.toLocal()),
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryDark,
            fitInsideHorizontally: true,
            getTooltipItems: (touched) {
              return [
                for (final spot in touched)
                  (spot.x.round() >= 0 && spot.x.round() < points.length)
                      ? LineTooltipItem(
                          '${DateFormat('MMM d').format(points[spot.x.round()].day.toLocal())}\n${spot.y.toInt()}',
                          AppTypography.caption.copyWith(
                            color: AppColors.surface,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
              ];
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.primary,
            barWidth: 2,
            dotData: FlDotData(
              show: points.length <= 7,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.primary,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  int _labelEvery(int length) {
    if (length <= 7) return 1;
    if (length <= 30) return 5;
    return 14;
  }

  double _interval(double top) {
    if (top <= 4) return 1;
    if (top <= 10) return 2;
    if (top <= 25) return 5;
    if (top <= 50) return 10;
    return (top / 4).ceilToDouble();
  }
}

class AdminDashboardSectionHeader extends StatelessWidget {
  const AdminDashboardSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTypography.subheading)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: AppTypography.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class AdminDashboardEmptyLine extends StatelessWidget {
  const AdminDashboardEmptyLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        message,
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class AdminDashboardSkeleton extends StatelessWidget {
  const AdminDashboardSkeleton({super.key, required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ShimmerBox(width: 220, height: 14),
        const SizedBox(height: 16),
        if (wide)
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: AdminOverviewCardSkeleton()),
              SizedBox(width: 12),
              Expanded(child: AdminOverviewCardSkeleton()),
              SizedBox(width: 12),
              Expanded(child: AdminOverviewCardSkeleton()),
              SizedBox(width: 12),
              Expanded(child: AdminOverviewCardSkeleton()),
            ],
          )
        else
          const Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: AdminOverviewCardSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AdminOverviewCardSkeleton()),
                ],
              ),
              SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: AdminOverviewCardSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AdminOverviewCardSkeleton()),
                ],
              ),
            ],
          ),
        const SizedBox(height: 28),
        const ShimmerBox(width: 180, height: 16),
        const SizedBox(height: 12),
        const ShimmerBox(width: double.infinity, height: 72, radius: 12),
        const SizedBox(height: 8),
        const ShimmerBox(width: double.infinity, height: 72, radius: 12),
      ],
    );
  }
}

class AdminPendingVerificationCard extends StatelessWidget {
  const AdminPendingVerificationCard({
    super.key,
    required this.shopName,
    required this.applicantName,
    required this.submittedAt,
    required this.onReview,
  });

  static const double cardHeight = 88;

  final String shopName;
  final String applicantName;
  final DateTime submittedAt;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cardHeight,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onReview,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.subheading,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        applicantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Submitted ${formatCompactDate(submittedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const AdminStatusChip(status: 'pending', label: 'Pending'),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
