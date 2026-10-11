import '../../../core/utils/formatters.dart';

/// Asia/Manila is UTC+8 and does not observe daylight saving.
const Duration manilaOffset = Duration(hours: 8);

enum AdminDashboardRange { allTime, today, weekly, monthly, yearly, custom }

enum AdminDashboardBucket { hour, day, month, year, auto }

String adminDashboardRangeLabel(AdminDashboardRange range) => switch (range) {
  AdminDashboardRange.allTime => 'All Time',
  AdminDashboardRange.today => 'Today',
  AdminDashboardRange.weekly => 'Weekly',
  AdminDashboardRange.monthly => 'Monthly',
  AdminDashboardRange.yearly => 'Yearly',
  AdminDashboardRange.custom => 'Custom Range',
};

/// Reporting window for the admin dashboard.
///
/// [from] is inclusive and [toExclusive] is exclusive, both in UTC.
/// [from] is null for All Time. Comparison bounds are null when the range
/// must not be compared.
class AdminDashboardPeriod {
  const AdminDashboardPeriod({
    required this.range,
    required this.from,
    required this.toExclusive,
    required this.bucket,
    this.compareFrom,
    this.compareTo,
    this.comparisonLabel,
    this.customStart,
    this.customEnd,
  });

  final AdminDashboardRange range;
  final DateTime? from;
  final DateTime toExclusive;
  final DateTime? compareFrom;
  final DateTime? compareTo;
  final AdminDashboardBucket bucket;
  final String? comparisonLabel;
  final DateTime? customStart;
  final DateTime? customEnd;

  bool get requestsComparison =>
      compareFrom != null &&
      compareTo != null &&
      compareTo!.isAfter(compareFrom!);

  String get bucketParam => switch (bucket) {
    AdminDashboardBucket.hour => 'hour',
    AdminDashboardBucket.day => 'day',
    AdminDashboardBucket.month => 'month',
    AdminDashboardBucket.year => 'year',
    AdminDashboardBucket.auto => 'auto',
  };

  String get chipLabel {
    if (range != AdminDashboardRange.custom ||
        customStart == null ||
        customEnd == null) {
      return adminDashboardRangeLabel(range);
    }
    final start = formatAdminPhilippinesDate(
      manilaStartUtc(customStart!.year, customStart!.month, customStart!.day),
    );
    final end = formatAdminPhilippinesDate(
      manilaStartUtc(customEnd!.year, customEnd!.month, customEnd!.day),
    );
    return '$start – $end';
  }

  factory AdminDashboardPeriod.today([DateTime? utcNow]) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    final wall = manilaWallClock(now);
    final from = manilaStartUtc(wall.year, wall.month, wall.day);
    return _elapsed(
      range: AdminDashboardRange.today,
      from: from,
      now: now,
      compareFrom: from.subtract(const Duration(days: 1)),
      bucket: AdminDashboardBucket.hour,
      comparisonLabel: 'vs yesterday',
    );
  }

  factory AdminDashboardPeriod.weekly([DateTime? utcNow]) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    final wall = manilaWallClock(now);
    final monday = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
    ).subtract(Duration(days: wall.weekday - DateTime.monday));
    final from = manilaStartUtc(monday.year, monday.month, monday.day);
    return _elapsed(
      range: AdminDashboardRange.weekly,
      from: from,
      now: now,
      compareFrom: from.subtract(const Duration(days: 7)),
      bucket: AdminDashboardBucket.day,
      comparisonLabel: 'vs previous week',
    );
  }

  factory AdminDashboardPeriod.monthly([DateTime? utcNow]) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    final wall = manilaWallClock(now);
    final from = manilaStartUtc(wall.year, wall.month, 1);
    final previous = wall.month == 1
        ? DateTime.utc(wall.year - 1, 12, 1)
        : DateTime.utc(wall.year, wall.month - 1, 1);
    final compareFrom = manilaStartUtc(previous.year, previous.month, 1);
    return _elapsed(
      range: AdminDashboardRange.monthly,
      from: from,
      now: now,
      compareFrom: compareFrom,
      compareEndLimit: from,
      bucket: AdminDashboardBucket.day,
      comparisonLabel: 'vs previous month',
    );
  }

  factory AdminDashboardPeriod.yearly([DateTime? utcNow]) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    final wall = manilaWallClock(now);
    final from = manilaStartUtc(wall.year, 1, 1);
    final compareFrom = manilaStartUtc(wall.year - 1, 1, 1);
    return _elapsed(
      range: AdminDashboardRange.yearly,
      from: from,
      now: now,
      compareFrom: compareFrom,
      compareEndLimit: from,
      bucket: AdminDashboardBucket.month,
      comparisonLabel: 'vs previous year',
    );
  }

  factory AdminDashboardPeriod.allTime([DateTime? utcNow]) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    return AdminDashboardPeriod(
      range: AdminDashboardRange.allTime,
      from: null,
      toExclusive: now,
      bucket: AdminDashboardBucket.auto,
    );
  }

  factory AdminDashboardPeriod.custom({
    required DateTime start,
    required DateTime end,
    DateTime? utcNow,
  }) {
    final now = (utcNow ?? DateTime.now()).toUtc();
    final today = _manilaDate(now);
    var startDay = DateTime.utc(start.year, start.month, start.day);
    var endDay = DateTime.utc(end.year, end.month, end.day);
    if (endDay.isBefore(startDay)) {
      final swap = startDay;
      startDay = endDay;
      endDay = swap;
    }
    if (startDay.isAfter(today)) startDay = today;
    if (endDay.isAfter(today)) endDay = today;
    final from = manilaStartUtc(startDay.year, startDay.month, startDay.day);
    final to = manilaStartUtc(
      endDay.year,
      endDay.month,
      endDay.day,
    ).add(const Duration(days: 1));
    return AdminDashboardPeriod(
      range: AdminDashboardRange.custom,
      from: from,
      toExclusive: to.isAfter(now) ? now : to,
      bucket: bucketForSpan(to.difference(from)),
      customStart: startDay,
      customEnd: endDay,
    );
  }

  static AdminDashboardPeriod _elapsed({
    required AdminDashboardRange range,
    required DateTime from,
    required DateTime now,
    required DateTime compareFrom,
    required AdminDashboardBucket bucket,
    required String comparisonLabel,
    DateTime? compareEndLimit,
  }) {
    final end = now.isAfter(from) ? now : from.add(const Duration(seconds: 1));
    final elapsed = end.difference(from);
    var compareTo = compareFrom.add(elapsed);
    if (compareEndLimit != null && compareTo.isAfter(compareEndLimit)) {
      compareTo = compareEndLimit;
    }
    final canCompare = compareTo.isAfter(compareFrom);
    return AdminDashboardPeriod(
      range: range,
      from: from,
      toExclusive: end,
      compareFrom: canCompare ? compareFrom : null,
      compareTo: canCompare ? compareTo : null,
      bucket: bucket,
      comparisonLabel: canCompare ? comparisonLabel : null,
    );
  }
}

DateTime manilaWallClock(DateTime instant) => instant.toUtc().add(manilaOffset);

DateTime manilaStartUtc(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) {
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
  ).subtract(manilaOffset);
}

AdminDashboardBucket bucketForSpan(Duration span) {
  if (span <= const Duration(days: 2)) return AdminDashboardBucket.hour;
  if (span <= const Duration(days: 62)) return AdminDashboardBucket.day;
  if (span <= const Duration(days: 730)) return AdminDashboardBucket.month;
  return AdminDashboardBucket.year;
}

DateTime _manilaDate(DateTime utcNow) {
  final wall = manilaWallClock(utcNow);
  return DateTime.utc(wall.year, wall.month, wall.day);
}
