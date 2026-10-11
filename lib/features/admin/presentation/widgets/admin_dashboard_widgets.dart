import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_dashboard_models.dart';
import '../../data/admin_marketplace_dashboard.dart';
import '../../domain/admin_dashboard_comparison.dart';
import '../../domain/admin_dashboard_period.dart';
import 'admin_review_widgets.dart';

final _countFormat = NumberFormat.decimalPattern();

class AdminDashboardBanner extends StatelessWidget {
  const AdminDashboardBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          message,
          style: AppTypography.caption.copyWith(
            color: AppColors.warningForeground,
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
    this.displayValue,
    this.onTap,
    this.attention = false,
  });

  final String label;
  final int value;
  final String? displayValue;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;
  final bool attention;

  static const double cardHeight = 118;

  @override
  Widget build(BuildContext context) {
    final primaryFigure = displayValue ?? _countFormat.format(value);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              Spacer(),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: attention ? AppColors.primary : AppColors.textHint,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            primaryFigure,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.heading.copyWith(fontSize: 20),
          ),
          SizedBox(height: 2),
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
      label: '$label, $primaryFigure. $detail',
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
    return SizedBox(
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

class AdminDashboardDateRangeBar extends StatelessWidget {
  const AdminDashboardDateRangeBar({
    super.key,
    required this.window,
    required this.onPresetSelected,
  });

  final AdminDateWindow window;
  final Future<void> Function(AdminDatePreset preset) onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final customCaption = window.preset == AdminDatePreset.custom
        ? window.chipLabel
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < AdminDatePreset.values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _AdminDateSegment(
                      label: adminDatePresetSegmentLabel(
                        AdminDatePreset.values[i],
                      ),
                      selected: window.preset == AdminDatePreset.values[i],
                      onTap: () => onPresetSelected(AdminDatePreset.values[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (customCaption != null) ...[
          SizedBox(height: 8),
          Text(
            customCaption,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminDateSegment extends StatefulWidget {
  const _AdminDateSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AdminDateSegment> createState() => _AdminDateSegmentState();
}

class _AdminDateSegmentState extends State<_AdminDateSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final background = selected
        ? AppColors.primary.withValues(alpha: 0.12)
        : _hovered
        ? AppColors.surfaceVariant
        : Colors.transparent;
    final borderColor = selected ? AppColors.primary : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hover) => setState(() => _hovered = hover),
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              border: Border.all(color: borderColor, width: selected ? 1 : 0),
            ),
            child: Text(
              widget.label,
              style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
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
              SizedBox(height: 12),
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
              FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
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
          side: BorderSide(color: AppColors.border),
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
                      SizedBox(height: 2),
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

class AdminDashboardPeriodBar extends StatelessWidget {
  const AdminDashboardPeriodBar({
    super.key,
    required this.period,
    required this.onSelected,
  });

  final AdminDashboardPeriod period;
  final Future<void> Function(AdminDashboardRange range) onSelected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var i = 0;
                    i < AdminDashboardRange.values.length;
                    i++
                  ) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _AdminDateSegment(
                      label: adminDashboardRangeLabel(
                        AdminDashboardRange.values[i],
                      ),
                      selected: period.range == AdminDashboardRange.values[i],
                      onTap: () => onSelected(AdminDashboardRange.values[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (period.range == AdminDashboardRange.custom) ...[
          const SizedBox(height: 8),
          Text(
            period.chipLabel,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

Future<AdminDashboardPeriod?> showAdminDashboardRangePicker(
  BuildContext context, {
  AdminDashboardPeriod? initial,
}) {
  final wall = manilaWallClock(DateTime.now().toUtc());
  final today = DateTime(wall.year, wall.month, wall.day);
  var start = initial?.customStart == null
      ? today
      : DateTime(
          initial!.customStart!.year,
          initial.customStart!.month,
          initial.customStart!.day,
        );
  var end = initial?.customEnd == null
      ? today
      : DateTime(
          initial!.customEnd!.year,
          initial.customEnd!.month,
          initial.customEnd!.day,
        );
  if (start.isAfter(today)) start = today;
  if (end.isAfter(today)) end = today;

  return showDialog<AdminDashboardPeriod>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pick({required bool isStart}) async {
            final picked = await showDatePicker(
              context: context,
              initialDate: isStart ? start : end,
              firstDate: DateTime(2020),
              lastDate: today,
            );
            if (picked == null) return;
            setState(() {
              final day = DateTime(picked.year, picked.month, picked.day);
              if (isStart) {
                start = day;
                if (end.isBefore(start)) end = start;
              } else {
                end = day;
                if (end.isBefore(start)) start = end;
              }
            });
          }

          return AlertDialog(
            title: const Text('Custom range'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dates use Philippine time.'),
                const SizedBox(height: 8),
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
                onPressed: end.isBefore(start)
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop(
                          AdminDashboardPeriod.custom(start: start, end: end),
                        );
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

class AdminKpiTile extends StatelessWidget {
  const AdminKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.delta,
  });

  final String label;
  final String value;
  final String caption;
  final AdminPeriodDelta? delta;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final deltaColor = switch (delta?.tone) {
      AdminDeltaTone.positive => AppColors.success,
      AdminDeltaTone.negative => AppColors.error,
      _ => AppColors.textSecondary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.heading.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption,
            ),
            if (delta != null) ...[
              const SizedBox(height: 8),
              Text(
                delta!.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: deltaColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminDashboardPanel extends StatelessWidget {
  const AdminDashboardPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.subheading),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class AdminStatLine extends StatelessWidget {
  const AdminStatLine({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            ),
          ),
          if (note != null) ...[
            Text(
              note!,
              style: AppTypography.caption.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class AdminAttentionLine extends StatelessWidget {
  const AdminAttentionLine({
    super.key,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final waiting = count > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              formatDashboardCount(count),
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w700,
                color: waiting
                    ? AppColors.warningForeground
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class AdminActivityRow extends StatelessWidget {
  const AdminActivityRow({super.key, required this.item, this.onTap});

  final AdminRecentActivity item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final actor = switch (item.actor) {
      'admin' => 'Admin',
      'system' => 'System',
      _ => 'Member',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppTypography.body),
                  if (item.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    actor,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                formatAdminReportDateTime(item.occurredAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class AdminRevenueChart extends StatelessWidget {
  const AdminRevenueChart({
    super.key,
    required this.points,
    required this.bucket,
    required this.showComparison,
  });

  final List<AdminRevenuePoint> points;
  final AdminDashboardBucket bucket;
  final bool showComparison;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette;
    final hasComparison =
        showComparison && points.any((point) => point.previous != null);
    final empty =
        points.isEmpty ||
        points.every(
          (point) =>
              point.current == 0 &&
              (point.previous == null || point.previous == 0),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform revenue', style: AppTypography.subheading),
            const SizedBox(height: 2),
            Text(
              'ThriftLine fees on paid orders that have not been refunded.',
              style: AppTypography.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
            if (hasComparison) ...[
              const SizedBox(height: 10),
              const _RevenueLegend(),
            ],
            const SizedBox(height: 12),
            if (empty)
              const AdminDashboardEmptyLine(
                'No platform revenue in this period.',
              )
            else
              SizedBox(
                height: 260,
                width: double.infinity,
                child: _RevenuePlot(
                  points: points,
                  bucket: bucket,
                  dark: dark,
                  showComparison: hasComparison,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RevenueLegend extends StatelessWidget {
  const _RevenueLegend();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        _LegendSwatch(
          color: dark ? const Color(0xFF5EEAD4) : AppPalette.brandPrimary,
          dashed: false,
          label: 'Current period',
        ),
        const SizedBox(width: 16),
        _LegendSwatch(
          color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          dashed: true,
          label: 'Previous period',
        ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: dashed ? 0 : 8,
          decoration: dashed
              ? null
              : BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
          child: dashed
              ? Align(
                  alignment: Alignment.center,
                  child: Container(height: 2, color: color),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

class _RevenuePlot extends StatelessWidget {
  const _RevenuePlot({
    required this.points,
    required this.bucket,
    required this.dark,
    required this.showComparison,
  });

  final List<AdminRevenuePoint> points;
  final AdminDashboardBucket bucket;
  final bool dark;
  final bool showComparison;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final line = dark ? const Color(0xFF5EEAD4) : AppPalette.brandPrimary;
    final previousColor = dark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    var maxY = 0.0;
    for (final point in points) {
      if (point.current > maxY) maxY = point.current;
      final previous = point.previous;
      if (previous != null && previous > maxY) maxY = previous;
    }
    final top = maxY <= 0 ? 1.0 : maxY * 1.18;
    final currentSpots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].current),
    ];
    final previousSpots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].previous ?? 0),
    ];
    final labelEvery = _labelEvery(points.length);
    final grid = palette.border.withValues(alpha: dark ? 0.55 : 1);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(1, 100000).toDouble(),
        minY: 0,
        maxY: top,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _interval(top),
          getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 72,
              interval: _interval(top),
              getTitlesWidget: (value, _) {
                if (value < 0 || value > top + 0.001) {
                  return const SizedBox.shrink();
                }
                return Text(
                  formatDashboardPeso(value),
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                if (index % labelEvery != 0 && index != points.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    adminRevenueAxisLabel(points[index].at, bucket),
                    style: AppTypography.caption.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                dark ? const Color(0xFF0F172A) : const Color(0xFF134E4A),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touched) {
              return [
                for (final spot in touched)
                  spot.barIndex == 0 &&
                          spot.x.round() >= 0 &&
                          spot.x.round() < points.length
                      ? LineTooltipItem(
                          _tooltip(
                            points[spot.x.round()],
                            bucket,
                            showComparison,
                          ),
                          AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        )
                      : null,
              ];
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: currentSpots,
            isCurved: currentSpots.length > 2,
            curveSmoothness: 0.22,
            color: line,
            barWidth: 2.5,
            shadow: Shadow(
              color: line.withValues(alpha: dark ? 0.45 : 0.18),
              blurRadius: dark ? 8 : 4,
            ),
            dotData: FlDotData(show: currentSpots.length <= 14),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  line.withValues(alpha: dark ? 0.28 : 0.22),
                  line.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          if (showComparison)
            LineChartBarData(
              spots: previousSpots,
              isCurved: previousSpots.length > 2,
              curveSmoothness: 0.22,
              color: previousColor,
              barWidth: 1.5,
              dashArray: const [5, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  int _labelEvery(int length) {
    if (length <= 8) return 1;
    if (length <= 16) return 2;
    if (length <= 31) return 5;
    return 4;
  }

  double _interval(double top) {
    if (top <= 4) return 1;
    if (top <= 20) return 5;
    if (top <= 100) return 25;
    if (top <= 1000) return 250;
    return (top / 4).ceilToDouble();
  }
}

String adminRevenueAxisLabel(DateTime at, AdminDashboardBucket bucket) {
  final wall = toPhilippinesTime(at);
  return switch (bucket) {
    AdminDashboardBucket.hour => DateFormat('h a').format(wall),
    AdminDashboardBucket.day => DateFormat('MMM d').format(wall),
    AdminDashboardBucket.month => DateFormat('MMM yyyy').format(wall),
    AdminDashboardBucket.year ||
    AdminDashboardBucket.auto => DateFormat('yyyy').format(wall),
  };
}

String _tooltip(
  AdminRevenuePoint point,
  AdminDashboardBucket bucket,
  bool showComparison,
) {
  final when = adminRevenueAxisLabel(point.at, bucket);
  final current = formatDashboardPeso(point.current);
  if (!showComparison || point.previous == null) {
    return '$when\n$current';
  }
  return '$when\nCurrent $current\nPrevious ${formatDashboardPeso(point.previous!)}';
}
