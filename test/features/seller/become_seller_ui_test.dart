import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/seller_id_type.dart';
import 'package:thriftline/features/seller/presentation/widgets/seller_id_type_list.dart';
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

  testWidgets('only the six allowed ID types are listed as accepted', (
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
    expect(find.text('Digital National ID'), findsOneWidget);
    expect(find.text("Driver's License"), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('SSS ID'), findsOneWidget);
    expect(find.text('UMID'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text("Voter's ID"), findsNothing);
    expect(find.text('PhilHealth ID'), findsNothing);
  });

  testWidgets('the ID list only offers supported types and reports the tap', (
    tester,
  ) async {
    SellerIdType? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerIdTypeList(
            selected: SellerIdType.nationalId,
            onSelected: (type) => picked = type,
          ),
        ),
      ),
    );

    expect(find.text('National ID'), findsOneWidget);
    expect(find.text('Digital National ID'), findsOneWidget);
    expect(find.text("Driver's License"), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('SSS ID'), findsOneWidget);
    expect(find.text('UMID'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text("Voter's ID"), findsNothing);
    expect(find.text('PhilHealth ID'), findsNothing);

    await tester.tap(find.text("Driver's License"));
    expect(picked, SellerIdType.driversLicense);
  });
}
