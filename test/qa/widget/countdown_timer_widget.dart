import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/widgets/countdown_timer.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void countdownTimerWidgetTests() {
  qaGroup('CountdownTimer', () {
    qaWidgetTest('shows the remaining time with the default format', (
      tester,
    ) async {
      final end = DateTime.now().add(
        const Duration(hours: 2, minutes: 5, seconds: 30),
      );
      await tester.pumpWidget(_host(CountdownTimer(endTime: end)));

      expect(find.text('02:05'), findsOneWidget);
    });

    qaWidgetTest('supports a custom format', (tester) async {
      final end = DateTime.now().add(const Duration(hours: 3, minutes: 30));
      await tester.pumpWidget(
        _host(
          CountdownTimer(
            endTime: end,
            format: (remaining) => '${remaining.inHours}h left',
          ),
        ),
      );

      expect(find.text('3h left'), findsOneWidget);
    });

    qaWidgetTest('expired auction shows "Ended" and fires onExpired once', (
      tester,
    ) async {
      var expired = 0;
      await tester.pumpWidget(
        _host(
          CountdownTimer(
            endTime: DateTime.now().subtract(const Duration(minutes: 1)),
            onExpired: () => expired++,
          ),
        ),
      );

      expect(find.text('Ended'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(expired, 1);
    });

    qaWidgetTest('updating endTime refreshes the display', (tester) async {
      var expired = 0;
      Widget build(DateTime end) =>
          _host(CountdownTimer(endTime: end, onExpired: () => expired++));

      await tester.pumpWidget(
        build(DateTime.now().add(const Duration(hours: 1, seconds: 30))),
      );
      expect(find.text('01:00'), findsOneWidget);

      await tester.pumpWidget(
        build(DateTime.now().subtract(const Duration(seconds: 5))),
      );
      await tester.pump();
      expect(find.text('Ended'), findsOneWidget);
      expect(expired, 1);
    });

    qaWidgetTest('timer is cancelled when the widget is removed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CountdownTimer(
            endTime: DateTime.now().add(const Duration(minutes: 10)),
          ),
        ),
      );
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(CountdownTimer), findsNothing);
    });
  });
}
