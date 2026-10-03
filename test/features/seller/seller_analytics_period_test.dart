import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_analytics_comparison.dart';
import 'package:thriftline/features/seller/data/seller_analytics_period.dart';

void main() {
  final now = DateTime(2026, 3, 15, 14, 30);

  test('last 7 days is a rolling 7-day window ending tomorrow', () {
    final w = resolveSellerAnalyticsPeriod(
      preset: SellerAnalyticsPreset.last7Days,
      now: now,
    );
    expect(w.rangeEnd, DateTime(2026, 3, 16));
    expect(w.rangeStart, DateTime(2026, 3, 9));
    expect(w.compareEnd, DateTime(2026, 3, 9));
    expect(w.compareStart, DateTime(2026, 3, 2));
  });

  test('last month is the previous calendar month', () {
    final w = resolveSellerAnalyticsPeriod(
      preset: SellerAnalyticsPreset.lastMonth,
      now: now,
    );
    expect(w.rangeStart, DateTime(2026, 2, 1));
    expect(w.rangeEnd, DateTime(2026, 3, 1));
    expect(w.compareStart, DateTime(2026, 1, 1));
    expect(w.compareEnd, DateTime(2026, 2, 1));
  });

  test('custom range rejects inverted dates', () {
    expect(
      () => resolveSellerAnalyticsPeriod(
        preset: SellerAnalyticsPreset.custom,
        customStartLocal: DateTime(2026, 3, 30),
        customEndLocal: DateTime(2026, 3, 1),
        now: now,
      ),
      throwsA(isA<SellerAnalyticsPeriodException>()),
    );
  });

  group('comparison copy', () {
    test('handles previous zero safely', () {
      final c = SellerAnalyticsComparison.fromCentavos(
        current: 500000,
        previous: 0,
        includeComparison: true,
      );
      expect(c.label, contains('₱0'));
    });

    test('20 percent higher', () {
      final c = SellerAnalyticsComparison.fromCentavos(
        current: 120000,
        previous: 100000,
        includeComparison: true,
      );
      expect(c.label, contains('20'));
      expect(c.label, contains('higher'));
    });
  });
}
