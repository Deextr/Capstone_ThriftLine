import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/seller_id_type.dart';
import 'package:thriftline/features/seller/presentation/widgets/terms_acceptance_note.dart';

void main() {
  testWidgets(
    'terms note is visible and names ThriftLine Terms and Conditions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TermsAcceptanceNote())),
      );

      expect(
        find.textContaining('By proceeding, you are accepting ThriftLine'),
        findsOneWidget,
      );
      expect(find.textContaining('Terms and Conditions'), findsOneWidget);
    },
  );

  testWidgets('only the five allowed ID types are listed as accepted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final type in SellerIdType.values)
                Chip(label: Text(type.label)),
            ],
          ),
        ),
      ),
    );

    expect(find.text('National ID'), findsOneWidget);
    expect(find.text("Driver's License"), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('SSS ID'), findsOneWidget);
    expect(find.text('UMID ID'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text("Voter's ID"), findsNothing);
    expect(find.text('PhilHealth ID'), findsNothing);
  });
}
