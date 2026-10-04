import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/constants/app_colors.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/utils/extensions.dart';
import 'package:thriftline/core/utils/responsive.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

Future<BuildContext> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void responsiveWidgetTests() {
  qaGroup('Responsive layout', () {
    qaWidgetTest('phone width (400px) is mobile with 2 columns', (
      tester,
    ) async {
      final context = await _pumpAtWidth(tester, 400);

      expect(Responsive.isMobile(context), isTrue);
      expect(Responsive.isTablet(context), isFalse);
      expect(Responsive.gridColumns(context), 2);
      expect(
        Responsive.horizontalPadding(context).left,
        AppConstants.spacingMd,
      );
    });

    qaWidgetTest('tablet width (800px) uses 3 columns', (tester) async {
      final context = await _pumpAtWidth(tester, 800);

      expect(Responsive.isTablet(context), isTrue);
      expect(Responsive.gridColumns(context), 3);
      expect(
        Responsive.horizontalPadding(context).left,
        AppConstants.spacingXl,
      );
    });

    qaWidgetTest('desktop width (1280px) uses 4 columns', (tester) async {
      final context = await _pumpAtWidth(tester, 1280);

      expect(Responsive.isDesktop(context), isTrue);
      expect(Responsive.gridColumns(context), 4);
      expect(
        Responsive.value<String>(
          context: context,
          mobile: 'm',
          tablet: 't',
        ),
        'm',
        reason: 'falls back to mobile when no desktop value is given',
      );
    });

    qaWidgetTest('context.screenSize reflects the view size', (tester) async {
      final context = await _pumpAtWidth(tester, 400);
      expect(context.screenSize, const Size(400, 900));
    });
  });

  qaGroup('Snack bars', () {
    qaWidgetTest('context.showSnackBar uses the error colour on error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    context.showSnackBar('Upload failed', isError: true),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.text('Upload failed'), findsOneWidget);
      final context = tester.element(find.text('trigger'));
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Theme.of(context).colorScheme.error);
    });

    qaWidgetTest('showThriftSnackBar floats with app colours', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showThriftSnackBar(context, 'Saved!'),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('save'));
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(find.text('Saved!'), findsOneWidget);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.backgroundColor, AppColors.textPrimary);
    });
  });
}
