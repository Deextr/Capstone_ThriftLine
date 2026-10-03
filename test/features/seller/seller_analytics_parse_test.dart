import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_analytics.dart';

void main() {
  test('tryParseRpc maps successful empty report', () {
    final report = SellerAnalyticsReport.tryParseRpc(
      {
        'success': true,
        'earnings_centavos': 0,
        'previous_earnings_centavos': 0,
        'products_sold': 0,
        'previous_products_sold': 0,
        'completed_orders': 0,
        'chart': [],
        'recent_sales': [],
      },
      includeComparison: true,
    );

    expect(report, isNotNull);
    expect(report!.earningsCentavos, 0);
    expect(report.chart, isEmpty);
    expect(report.recentSales, isEmpty);
  });

  test('tryParseRpc returns null when success is false', () {
    expect(
      SellerAnalyticsReport.tryParseRpc(
        {'success': false, 'error': 'Please sign in.'},
        includeComparison: false,
      ),
      isNull,
    );
  });
}
