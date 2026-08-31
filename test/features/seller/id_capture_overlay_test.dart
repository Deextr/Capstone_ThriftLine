import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/presentation/widgets/id_capture_overlay.dart';

void main() {
  testWidgets('red frame asks the user to place the ID', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 250,
          child: IdCaptureOverlay(),
        ),
      ),
    );
    expect(find.text('PLACE ID HERE'), findsOneWidget);
    expect(find.text('Place ID inside the frame'), findsOneWidget);
  });

  testWidgets('green frame tells the user to hold still', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 250,
          child: IdCaptureOverlay(aligned: true),
        ),
      ),
    );
    expect(find.text('PLACE ID HERE'), findsNothing);
    expect(find.text('ID in frame — hold still'), findsOneWidget);
  });
}
