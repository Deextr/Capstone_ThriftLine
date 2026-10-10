import 'package:intl/intl.dart';

enum AdminDeltaTone { positive, negative, neutral }

class AdminPeriodDelta {
  const AdminPeriodDelta({required this.text, required this.tone});

  final String text;
  final AdminDeltaTone tone;
}

final _dashboardPeso = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

final _dashboardCount = NumberFormat.decimalPattern();

String formatDashboardPeso(num amount) => _dashboardPeso.format(amount);

String formatDashboardCount(num amount) =>
    _dashboardCount.format(amount.round());

/// Builds a comparison line only when the previous period is real.
///
/// A previous value of zero still produces an absolute change. It does not
/// produce a percentage. A missing previous value hides the line.
AdminPeriodDelta? formatAdminPeriodDelta({
  required num current,
  required num? previous,
  required bool comparisonAvailable,
  required String? comparisonLabel,
  required bool higherIsBetter,
  String unit = '',
  bool currency = false,
}) {
  final label = comparisonLabel?.trim() ?? '';
  if (!comparisonAvailable || previous == null || label.isEmpty) return null;

  final delta = current - previous;
  final tone = delta == 0
      ? AdminDeltaTone.neutral
      : _improves(delta, higherIsBetter)
      ? AdminDeltaTone.positive
      : AdminDeltaTone.negative;

  if (delta == 0) {
    return AdminPeriodDelta(text: 'No change $label', tone: tone);
  }

  final magnitude = currency
      ? formatDashboardPeso(delta.abs())
      : formatDashboardCount(delta.abs());
  final signed = '${delta > 0 ? '+' : '-'}$magnitude';
  final amount = currency || unit.isEmpty
      ? signed
      : '$signed ${_plural(delta.abs(), unit)}';

  if (previous == 0) {
    return AdminPeriodDelta(text: '$amount $label', tone: tone);
  }

  final percent = (delta / previous) * 100;
  final percentText =
      '${delta > 0 ? '+' : '-'}${percent.abs().toStringAsFixed(1)}%';
  return AdminPeriodDelta(text: '$amount ($percentText) $label', tone: tone);
}

bool _improves(num delta, bool higherIsBetter) =>
    higherIsBetter ? delta > 0 : delta < 0;

String _plural(num absolute, String singular) {
  if (absolute == 1) return singular;
  if (singular.endsWith('s')) return singular;
  return '${singular}s';
}
