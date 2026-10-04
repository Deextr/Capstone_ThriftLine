import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/trust_safety/presentation/widgets/star_rating_input.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void starRatingWidgetTests() {
  qaGroup('StarRatingInput', () {
    qaWidgetTest('fills stars up to the current value', (tester) async {
      await tester.pumpWidget(_host(StarRatingInput(value: 3, onChanged: (_) {})));

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(2));
      expect(_semanticsLabel('3 out of 5 stars'), findsOneWidget);
    });

    qaWidgetTest('tapping a star reports its rating', (tester) async {
      int? picked;
      await tester.pumpWidget(
        _host(StarRatingInput(value: 0, onChanged: (v) => picked = v)),
      );

      expect(_semanticsLabel('No rating selected'), findsOneWidget);
      await tester.tap(find.byTooltip('4 stars'));
      await tester.pump();
      expect(picked, 4);

      await tester.tap(find.byTooltip('1 star'));
      await tester.pump();
      expect(picked, 1);
    });

    qaWidgetTest('read-only mode disables every star', (tester) async {
      int? picked;
      await tester.pumpWidget(
        _host(
          StarRatingInput(value: 2, readOnly: true, onChanged: (v) => picked = v),
        ),
      );

      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons, hasLength(5));
      expect(buttons.every((b) => b.onPressed == null), isTrue);

      await tester.tap(find.byTooltip('5 stars'));
      await tester.pump();
      expect(picked, isNull);
    });
  });

  qaGroup('StarRatingReadout', () {
    qaWidgetTest('rounds the average and shows the number', (tester) async {
      await tester.pumpWidget(
        _host(const StarRatingReadout(value: 3.6, showNumber: true)),
      );

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(1));
      expect(find.text('3.6'), findsOneWidget);
    });

    qaWidgetTest('clamps out-of-range values to 0..5 stars', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarRatingReadout(value: 7.2),
              StarRatingReadout(value: -1),
            ],
          ),
        ),
      );

      // 5 filled from the first readout, 5 empty from the second.
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(5));
      expect(find.text('7.2'), findsNothing);
    });
  });
}
