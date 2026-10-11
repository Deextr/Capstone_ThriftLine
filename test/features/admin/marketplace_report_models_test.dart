import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/marketplace_report_models.dart';

void main() {
  test('parses payments summary and distinguishes platform revenue label', () {
    const json = {
      'success': true,
      'category': 'payments',
      'summary': [
        {
          'key': 'gross_payment_volume',
          'label': 'Gross payment volume',
          'value': 5000,
          'kind': 'money',
          'display': '5,000.00',
          'snapshot': false,
        },
        {
          'key': 'net_platform_revenue',
          'label': 'Net platform revenue (fees, non-refunded)',
          'value': 100,
          'kind': 'money',
          'display': '100.00',
          'snapshot': false,
        },
      ],
      'comparison': [],
      'breakdowns': [],
      'details': {'columns': [], 'rows': [], 'total': 0, 'truncated': false},
      'detail_total': 0,
      'limitations': [
        'Buyer payment totals are not platform revenue.',
      ],
    };

    final payload = MarketplaceReportPayload.fromJson(json);
    expect(payload.success, isTrue);
    expect(payload.summary.length, 2);
    expect(payload.summary.first.key, 'gross_payment_volume');
    expect(payload.summary.last.key, 'net_platform_revenue');
    expect(
      payload.summary.last.label.toLowerCase(),
      isNot(contains('buyer payment total')),
    );
    expect(payload.limitations.first, contains('not platform revenue'));
  });

  test('parses detail rows when nested jsonb maps are not Map<String, dynamic>', () {
    final details = <dynamic, dynamic>{
      'columns': <dynamic>['Registered', 'Status'],
      'rows': <dynamic>[
        <dynamic>['2026-01-02 08:00', 'active'],
      ],
      'total': 1,
      'truncated': false,
    };
    final json = Map<String, dynamic>.from(<dynamic, dynamic>{
      'success': true,
      'category': 'users',
      'summary': <dynamic>[],
      'comparison': <dynamic>[],
      'breakdowns': <dynamic>[],
      'details': details,
      'detail_total': 1,
      'limitations': <dynamic>[],
    });

    final payload = MarketplaceReportPayload.fromJson(json);
    expect(payload.details.columns, ['Registered', 'Status']);
    expect(payload.details.rows.single, ['2026-01-02 08:00', 'active']);
    expect(payload.detailTotal, 1);
  });
}
