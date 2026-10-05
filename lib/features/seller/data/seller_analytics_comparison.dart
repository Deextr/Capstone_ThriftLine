/// Human-readable period comparison (no Infinity/NaN).
class SellerAnalyticsComparison {
  const SellerAnalyticsComparison({
    required this.hasComparison,
    required this.label,
    this.percentChange,
    this.current = 0,
    this.previous = 0,
  });

  final bool hasComparison;
  final String label;
  final double? percentChange;
  final num current;
  final num previous;

  /// Short trend for cards, e.g. `↑ 12.5%` or `↓ 8%`.
  String? get shortTrendText {
    if (!hasComparison) return null;
    if (previous <= 0 && current > 0) return null;
    if (previous <= 0 && current <= 0) return '→ 0%';
    if (percentChange == null) return null;
    if (percentChange == 0) return '→ 0%';
    final abs = percentChange!.abs();
    final formatted = abs >= 10
        ? abs.round().toString()
        : abs.toStringAsFixed(1);
    return percentChange! > 0 ? '↑ $formatted%' : '↓ $formatted%';
  }

  bool get noPreviousPeriodData =>
      hasComparison && previous <= 0 && current > 0;

  factory SellerAnalyticsComparison.fromCentavos({
    required int current,
    required int previous,
    required bool includeComparison,
  }) {
    return SellerAnalyticsComparison.fromValues(
      current: current,
      previous: previous,
      includeComparison: includeComparison,
    );
  }

  factory SellerAnalyticsComparison.fromValues({
    required num current,
    required num previous,
    required bool includeComparison,
  }) {
    if (!includeComparison) {
      return const SellerAnalyticsComparison(hasComparison: false, label: '');
    }
    if (previous <= 0 && current <= 0) {
      return SellerAnalyticsComparison(
        hasComparison: true,
        label: 'No change from previous period',
        percentChange: 0,
        current: current,
        previous: previous,
      );
    }
    if (previous <= 0 && current > 0) {
      return SellerAnalyticsComparison(
        hasComparison: true,
        label: 'Up from ₱0 in the previous period',
        current: current,
        previous: previous,
      );
    }
    if (current == previous) {
      return SellerAnalyticsComparison(
        hasComparison: true,
        label: 'No change from previous period',
        percentChange: 0,
        current: current,
        previous: previous,
      );
    }
    final pct = ((current - previous) / previous) * 100;
    final rounded = pct.abs() >= 10
        ? pct.roundToDouble()
        : double.parse(pct.toStringAsFixed(1));
    if (pct > 0) {
      return SellerAnalyticsComparison(
        hasComparison: true,
        label: '${rounded.abs()}% higher than previous period',
        percentChange: rounded,
        current: current,
        previous: previous,
      );
    }
    return SellerAnalyticsComparison(
      hasComparison: true,
      label: '${rounded.abs()}% lower than previous period',
      percentChange: rounded,
      current: current,
      previous: previous,
    );
  }
}
