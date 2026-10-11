import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/theme/app_theme.dart';
import 'package:thriftline/features/admin/data/admin_review_rules.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_review_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final longName = 'Maria Santos ${'Dela Cruz ' * 8}';

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required List<Widget> children,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final size in const [Size(320, 640), Size(360, 800), Size(412, 915)]) {
    for (final scale in [1.0, 1.4, 2.0]) {
      testWidgets('queue row ${size.width} x$scale', (tester) async {
        await pump(
          tester,
          size: size,
          textScale: scale,
          children: [
            AdminQueueNavRow(
              label: 'Seller Applications',
              detail: '2 awaiting review',
              loading: false,
              needsAttention: true,
              icon: Icons.storefront_outlined,
              semanticLabel: 'Seller Applications, 2 awaiting review',
              onTap: () {},
            ),
            AdminQueueItem(
              title: 'Item significantly different from listing',
              status: 'under_review',
              statusLabel: 'Under Review',
              lines: [longName, 'Reported by $longName'],
              meta: 'Sep 25 · 4 photos · Order #TL-10482',
              actionLabel: 'View report',
              onTap: () {},
            ),
            AdminFilterBar(value: AdminQueueFilter.open, onChanged: (_) {}),
            const AdminChoiceRow(
              label: 'Refund the buyer',
              hint: 'Refund ₱1,250.00 to buyer',
              selected: true,
              onTap: _noop,
            ),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AdminPhotoThumb(label: 'ID front', url: null),
                AdminPhotoThumb(label: 'ID back', url: null),
                AdminPhotoThumb(label: 'Selfie', url: null),
              ],
            ),
          ],
        );
        expect(find.text('Under Review'), findsOneWidget);
        expect(find.text('View report'), findsOneWidget);
        expect(find.text('Needs review'), findsOneWidget);
      });
    }
  }
}

void _noop() {}
