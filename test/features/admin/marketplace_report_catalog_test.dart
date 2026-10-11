import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/features/admin/domain/marketplace_report_catalog.dart';

void main() {
  group('MarketplaceReportDateWindow', () {
    test('last7Days uses half-open Manila window', () {
      final utcNow = DateTime.utc(2026, 3, 15, 10);
      final window = MarketplaceReportDateWindow.last7Days(utcNow);
      expect(window.elapsed, const Duration(days: 7));
    });

    test('thisYear is year-to-date through today in Manila', () {
      final utcNow = DateTime.utc(2026, 6, 10, 16);
      final window = MarketplaceReportDateWindow.thisYear(utcNow);
      expect(window.yearToDate, isTrue);
      expect(window.chipLabel, 'Yearly');
    });

    test('comparison previous period shifts by elapsed duration', () {
      final window = MarketplaceReportDateWindow.last7Days(DateTime.utc(2026, 3, 15));
      final prev = window.comparisonWindow(
        MarketplaceReportComparisonMode.previousPeriod,
      );
      expect(prev, isNotNull);
      expect(prev!.toExclusive, window.from);
      expect(prev.elapsed, window.elapsed);
    });

    test('Feb 29 last year shifts to Feb 28', () {
      final utcNow = DateTime.utc(2028, 2, 29, 12);
      final window = MarketplaceReportDateWindow.today(utcNow);
      final prev = window.comparisonWindow(
        MarketplaceReportComparisonMode.samePeriodLastYear,
      );
      expect(prev, isNotNull);
      expect(prev!.manilaFrom.month, 2);
      expect(prev.manilaFrom.day, lessThanOrEqualTo(28));
    });
  });

  group('marketplaceReportPercentChange', () {
    test('returns null when previous is zero', () {
      expect(marketplaceReportPercentChange(10, 0), isNull);
    });

    test('computes percentage change', () {
      expect(marketplaceReportPercentChange(120, 100), 20);
    });
  });

  group('sanitizeSpreadsheetCell', () {
    test('prefixes formula-like values', () {
      expect(sanitizeSpreadsheetCell('=1+1'), startsWith("'"));
      expect(sanitizeSpreadsheetCell('-100'), startsWith("'"));
    });
  });

  group('formatAdminReportDateTime', () {
    test('formats Manila wall time as OCT 3, 2026 6:35 AM', () {
      // Oct 3, 2026 06:35 PHT = Oct 2, 2026 22:35 UTC
      final utc = DateTime.utc(2026, 10, 2, 22, 35);
      expect(formatAdminReportDateTime(utc), 'OCT 3, 2026 6:35 AM');
    });
  });

  group('formatAdminReportPesoAmount', () {
    test('normalizes mojibake and plain numbers to peso', () {
      expect(formatAdminReportPesoAmount('â‚±1,234.56'), '₱1,234.56');
      expect(formatAdminReportPesoAmount('1234.5'), '₱1,234.50');
    });
  });
}
