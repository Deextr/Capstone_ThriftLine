import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:thriftline/widgets/empty_state.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void thriftDisplayWidgetTests() {
  qaGroup('ThriftBadge / ThriftChip / ThriftCard', () {
    qaWidgetTest('ThriftBadge renders for every variant', (tester) async {
      await tester.pumpWidget(
        _host(
          Wrap(
            children: [
              for (final variant in BadgeVariant.values)
                ThriftBadge(label: variant.name, variant: variant),
            ],
          ),
        ),
      );

      for (final variant in BadgeVariant.values) {
        expect(find.text(variant.name), findsOneWidget);
      }
    });

    qaWidgetTest('ThriftChip reflects selection and reports taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(ThriftChip(label: 'Vintage', selected: true, onTap: () => taps++)),
      );

      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isTrue);

      await tester.tap(find.text('Vintage'));
      await tester.pump();
      expect(taps, 1);
    });

    qaWidgetTest('ThriftCard renders its child and handles taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(ThriftCard(onTap: () => taps++, child: const Text('Order #1'))),
      );

      await tester.tap(find.text('Order #1'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  qaGroup('EmptyState / ErrorState / ShimmerBox', () {
    qaWidgetTest('EmptyState shows icon, title and message only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Your cart is empty',
            message: 'Browse thrift finds to get started.',
          ),
        ),
      );

      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Browse thrift finds to get started.'), findsOneWidget);
      expect(find.byType(ThriftButton), findsNothing);
    });

    qaWidgetTest('EmptyState action button needs label AND callback', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              Expanded(
                child: EmptyState(
                  icon: Icons.search,
                  title: 'No results',
                  message: 'Try another keyword.',
                  actionLabel: 'Browse all',
                  onAction: () => taps++,
                ),
              ),
              const Expanded(
                child: EmptyState(
                  icon: Icons.search_off,
                  title: 'Nothing here',
                  message: 'No callback given.',
                  actionLabel: 'Hidden action',
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Browse all'), findsOneWidget);
      expect(find.text('Hidden action'), findsNothing);

      await tester.tap(find.text('Browse all'));
      await tester.pump();
      expect(taps, 1);
    });

    qaWidgetTest('ErrorState shows retry and calls onRetry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _host(
          ErrorState(
            message: 'Unable to load orders.',
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Unable to load orders.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });

    qaWidgetTest('ShimmerBox renders a shimmer of the given size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Center(child: ShimmerBox(width: 120, height: 20))),
      );

      expect(find.byType(Shimmer), findsOneWidget);
      final box = find.descendant(
        of: find.byType(ShimmerBox),
        matching: find.byType(Container),
      );
      expect(tester.getSize(box), const Size(120, 20));
    });
  });
}
