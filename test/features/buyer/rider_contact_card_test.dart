import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/shipment_model.dart';
import 'package:thriftline/widgets/rider_contact_card.dart';

void main() {
  testWidgets('shows the full rider number and contact actions', (
    tester,
  ) async {
    final shipment = ShipmentModel.fromSupabase({
      'shipment_id': 'ship-1',
      'order_id': 'order-1',
      'delivery_status': 'out_for_delivery',
      'delivery_method': 'freelance_rider',
      'rider_name': 'Juan Dela Cruz',
      'rider_phone': '09171234567',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerRiderContactCard(
            shipment: shipment,
            onCall: () {},
            onMessage: () {},
          ),
        ),
      ),
    );

    expect(find.text('Your Rider'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('0917 123 4567'), findsOneWidget);
    expect(find.textContaining('••'), findsNothing);
    expect(find.text('Call Rider'), findsOneWidget);
    expect(find.text('Message Rider'), findsOneWidget);
    expect(_actionButton(tester, 'Call Rider').onPressed, isNotNull);
    expect(_actionButton(tester, 'Message Rider').onPressed, isNotNull);
  });

  testWidgets('disables call actions when the rider number is missing', (
    tester,
  ) async {
    final shipment = ShipmentModel.fromSupabase({
      'shipment_id': 'ship-1',
      'order_id': 'order-1',
      'delivery_status': 'out_for_delivery',
      'delivery_method': 'freelance_rider',
      'rider_name': 'Juan Dela Cruz',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerRiderContactCard(
            shipment: shipment,
            onCall: () {},
            onMessage: () {},
          ),
        ),
      ),
    );

    expect(find.text('Contact number unavailable'), findsOneWidget);
    expect(find.text('0917 123 4567'), findsNothing);
    expect(_actionButton(tester, 'Call Rider').onPressed, isNull);
    expect(_actionButton(tester, 'Message Rider').onPressed, isNull);
  });

  testWidgets('hides the rider card before a rider is assigned', (
    tester,
  ) async {
    final shipment = ShipmentModel.fromSupabase({
      'shipment_id': 'ship-1',
      'order_id': 'order-1',
      'delivery_status': 'seller_preparing',
      'delivery_method': 'freelance_rider',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerRiderContactCard(
            shipment: shipment,
            onCall: () {},
            onMessage: () {},
          ),
        ),
      ),
    );

    expect(find.text('Your Rider'), findsNothing);
    expect(find.text('Call Rider'), findsNothing);
  });
}

ButtonStyleButton _actionButton(WidgetTester tester, String label) {
  return tester.widget<ButtonStyleButton>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        )
        .first,
  );
}
