import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/domain/admin_order_management.dart';
import 'package:thriftline/features/admin/presentation/widgets/admin_ui_components.dart';

void main() {
  testWidgets('AdminOrderTypeBadge shows compact fixed price label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: AdminOrderTypeBadge.forKind(AdminOrderKind.fixedPrice),
          ),
        ),
      ),
    );

    expect(find.text('Fixed price'), findsOneWidget);
    expect(find.text('Fixed Price'), findsNothing);
  });

  testWidgets('AdminOrderTypeBadge non-compact shows full fixed price label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminOrderTypeBadge.forKind(
            AdminOrderKind.fixedPrice,
            compact: false,
          ),
        ),
      ),
    );

    expect(find.text('Fixed Price'), findsOneWidget);
  });

  testWidgets('AdminOrderTypeBadge distinguishes auction orders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminOrderTypeBadge.forKind(AdminOrderKind.auction),
        ),
      ),
    );

    expect(find.text('Auction'), findsOneWidget);
  });
}
