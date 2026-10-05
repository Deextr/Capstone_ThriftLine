import 'package:flutter/foundation.dart';

enum SellerAnalyticsPreset {
  allTime,
  today,
  last7Days,
  lastMonth,
  lastYear,
  custom,
}

/// Resolved UTC instants for the current and comparison windows.
@immutable
class SellerAnalyticsPeriodWindow {
  const SellerAnalyticsPeriodWindow({
    required this.preset,
    required this.rangeStart,
    required this.rangeEnd,
    this.compareStart,
    this.compareEnd,
    required this.includeCompare,
    required this.chartBucket,
    this.customLabel,
  });

  final SellerAnalyticsPreset preset;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? compareStart;
  final DateTime? compareEnd;
  final bool includeCompare;
  final String chartBucket;
  final String? customLabel;

  String get periodLabel => switch (preset) {
    SellerAnalyticsPreset.allTime => 'All time',
    SellerAnalyticsPreset.today => 'Today',
    SellerAnalyticsPreset.last7Days => 'Last 7 days',
    SellerAnalyticsPreset.lastMonth => 'Last month',
    SellerAnalyticsPreset.lastYear => 'Last year',
    SellerAnalyticsPreset.custom => customLabel ?? 'Custom range',
  };

  /// Short label for trend lines under metric cards.
  String get vsPreviousLabel => switch (preset) {
    SellerAnalyticsPreset.allTime => '',
    SellerAnalyticsPreset.today => 'vs yesterday',
    SellerAnalyticsPreset.last7Days => 'vs previous 7 days',
    SellerAnalyticsPreset.lastMonth => 'vs month before',
    SellerAnalyticsPreset.lastYear => 'vs previous year',
    SellerAnalyticsPreset.custom => 'vs previous period',
  };

  String get currentPeriodComparisonTitle => switch (preset) {
    SellerAnalyticsPreset.today => 'Today vs yesterday',
    SellerAnalyticsPreset.last7Days => 'Last 7 days vs previous 7 days',
    SellerAnalyticsPreset.lastMonth => 'Last month vs month before',
    SellerAnalyticsPreset.lastYear => 'Last year vs previous year',
    SellerAnalyticsPreset.custom => '$periodLabel vs previous period',
    SellerAnalyticsPreset.allTime => '',
  };
}

DateTime _startOfLocalDay(DateTime local) =>
    DateTime(local.year, local.month, local.day);

DateTime _monthStart(int year, int month) => DateTime(year, month, 1);

/// Builds filter windows using the device local calendar.
SellerAnalyticsPeriodWindow resolveSellerAnalyticsPeriod({
  required SellerAnalyticsPreset preset,
  DateTime? customStartLocal,
  DateTime? customEndLocal,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final todayStart = _startOfLocalDay(clock);
  final tomorrowStart = todayStart.add(const Duration(days: 1));

  switch (preset) {
    case SellerAnalyticsPreset.allTime:
      return const SellerAnalyticsPeriodWindow(
        preset: SellerAnalyticsPreset.allTime,
        rangeStart: null,
        rangeEnd: null,
        includeCompare: false,
        chartBucket: 'month',
      );
    case SellerAnalyticsPreset.today:
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      return SellerAnalyticsPeriodWindow(
        preset: preset,
        rangeStart: todayStart,
        rangeEnd: tomorrowStart,
        compareStart: yesterdayStart,
        compareEnd: todayStart,
        includeCompare: true,
        chartBucket: 'day',
      );
    case SellerAnalyticsPreset.last7Days:
      final rangeStart = tomorrowStart.subtract(const Duration(days: 7));
      final compareEnd = rangeStart;
      final compareStart = compareEnd.subtract(const Duration(days: 7));
      return SellerAnalyticsPeriodWindow(
        preset: preset,
        rangeStart: rangeStart,
        rangeEnd: tomorrowStart,
        compareStart: compareStart,
        compareEnd: compareEnd,
        includeCompare: true,
        chartBucket: 'day',
      );
    case SellerAnalyticsPreset.lastMonth:
      final thisMonthStart = _monthStart(clock.year, clock.month);
      final lastMonthStart = clock.month == 1
          ? _monthStart(clock.year - 1, 12)
          : _monthStart(clock.year, clock.month - 1);
      final monthBeforeStart = lastMonthStart.month == 1
          ? _monthStart(lastMonthStart.year - 1, 12)
          : _monthStart(lastMonthStart.year, lastMonthStart.month - 1);
      return SellerAnalyticsPeriodWindow(
        preset: preset,
        rangeStart: lastMonthStart,
        rangeEnd: thisMonthStart,
        compareStart: monthBeforeStart,
        compareEnd: lastMonthStart,
        includeCompare: true,
        chartBucket: 'day',
      );
    case SellerAnalyticsPreset.lastYear:
      final thisYearStart = _monthStart(clock.year, 1);
      final lastYearStart = _monthStart(clock.year - 1, 1);
      final yearBeforeStart = _monthStart(clock.year - 2, 1);
      return SellerAnalyticsPeriodWindow(
        preset: preset,
        rangeStart: lastYearStart,
        rangeEnd: thisYearStart,
        compareStart: yearBeforeStart,
        compareEnd: lastYearStart,
        includeCompare: true,
        chartBucket: 'month',
      );
    case SellerAnalyticsPreset.custom:
      final start = customStartLocal;
      final end = customEndLocal;
      if (start == null || end == null) {
        return SellerAnalyticsPeriodWindow(
          preset: preset,
          rangeStart: todayStart,
          rangeEnd: tomorrowStart,
          compareStart: todayStart.subtract(const Duration(days: 1)),
          compareEnd: todayStart,
          includeCompare: true,
          chartBucket: 'day',
        );
      }
      final rangeStart = _startOfLocalDay(start);
      final rangeEnd = _startOfLocalDay(end).add(const Duration(days: 1));
      if (!rangeEnd.isAfter(rangeStart)) {
        throw SellerAnalyticsPeriodException.invalidCustomRange();
      }
      final duration = rangeEnd.difference(rangeStart);
      final compareEnd = rangeStart;
      final compareStart = compareEnd.subtract(duration);
      final label = '${_formatShort(start)} – ${_formatShort(end)}';
      final bucket = duration.inDays > 120 ? 'month' : 'day';
      return SellerAnalyticsPeriodWindow(
        preset: preset,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        compareStart: compareStart,
        compareEnd: compareEnd,
        includeCompare: true,
        chartBucket: bucket,
        customLabel: label,
      );
  }
}

String _formatShort(DateTime d) {
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

class SellerAnalyticsPeriodException implements Exception {
  SellerAnalyticsPeriodException(this.message);
  final String message;

  factory SellerAnalyticsPeriodException.invalidCustomRange() =>
      SellerAnalyticsPeriodException(
        'Start date must be on or before end date.',
      );
}
