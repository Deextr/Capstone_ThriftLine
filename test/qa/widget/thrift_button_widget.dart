import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void thriftButtonWidgetTests() {
  qaGroup('ThriftButton', () {
    qaWidgetTest('renders its label and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(ThriftButton(label: 'Checkout', onPressed: () => taps++)),
      );

      expect(find.text('Checkout'), findsOneWidget);
      await tester.tap(find.text('Checkout'));
      await tester.pump();
      expect(taps, 1);
    });

    qaWidgetTest('shows an optional leading icon', (tester) async {
      await tester.pumpWidget(
        _host(
          ThriftButton(
            label: 'Add to cart',
            icon: Icons.shopping_bag_outlined,
            onPressed: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    });

    qaWidgetTest('loading state shows spinner and blocks taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          ThriftButton(
            label: 'Pay now',
            loadingLabel: 'Processing…',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Processing…'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);

      await tester.tap(find.byType(ThriftButton));
      await tester.pump();
      expect(taps, 0);
    });

    qaWidgetTest('disabled primary button does not crash on tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ThriftButton(label: 'Disabled', onPressed: null)),
      );

      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(find.text('Disabled'), findsOneWidget);
    });

    qaWidgetTest('each variant renders the matching material button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ThriftButton(
                  label: 'Secondary',
                  variant: ThriftButtonVariant.secondary,
                  onPressed: () {},
                ),
                ThriftButton(
                  label: 'Outline',
                  variant: ThriftButtonVariant.outline,
                  onPressed: () {},
                ),
                ThriftButton(
                  label: 'Ghost',
                  variant: ThriftButtonVariant.ghost,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });
  });
}
