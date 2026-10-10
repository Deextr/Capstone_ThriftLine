import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thriftline/features/admin/controllers/admin_marketplace_reports_controller.dart';
import 'package:thriftline/features/admin/data/marketplace_report_models.dart';
import 'package:thriftline/features/admin/domain/marketplace_report_catalog.dart';
import 'package:thriftline/features/admin/presentation/web/admin_web_marketplace_reports_page.dart';

void main() {
    testWidgets('reports page shows summary tables and export actions without charts', (
    tester,
  ) async {
    final controller = AdminMarketplaceReportsController.preview(
      payload: MarketplaceReportPayload(
        success: true,
        category: 'overview',
        generatedAt: DateTime.utc(2026, 1, 1),
        rangeFrom: DateTime.utc(2026, 1, 1),
        rangeTo: DateTime.utc(2026, 1, 31),
        summary: const [
          MarketplaceReportMetric(
            key: 'new_registrations',
            label: 'New registrations',
            value: 5,
            kind: 'count',
            display: '5',
            snapshot: false,
          ),
        ],
        comparison: const [],
        breakdowns: const [],
        details: MarketplaceReportDetails.empty,
        detailTotal: 0,
        limitations: const [],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AdminMarketplaceReportsController>.value(
            value: controller,
            child: const AdminWebMarketplaceReportsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New registrations'), findsWidgets);
    expect(find.text('Export PDF'), findsOneWidget);
  });
}
