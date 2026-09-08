import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';
import 'package:thriftline/features/seller/presentation/widgets/id_capture_overlay.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: SizedBox(width: 400, height: 700, child: child));
  }

  testWidgets('searching frame asks the user to place the ID', (tester) async {
    await tester.pumpWidget(wrap(const IdCaptureOverlay()));
    expect(find.text('Place your ID within the frame'), findsOneWidget);
    expect(find.text('Photo will be taken automatically'), findsOneWidget);
  });

  testWidgets('misaligned frame asks the user to align the edges', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const IdCaptureOverlay(status: LiveIdStatus.poorlyFramed)),
    );
    expect(
      find.text('Align the edges of your ID within the frame'),
      findsOneWidget,
    );
    expect(find.text('PLACE ID HERE'), findsNothing);
  });

  testWidgets('valid frame tells the user to hold steady', (tester) async {
    await tester.pumpWidget(
      wrap(const IdCaptureOverlay(status: LiveIdStatus.aligned)),
    );
    expect(find.text('ID detected — hold steady'), findsOneWidget);
    expect(find.text('Photo will be taken automatically'), findsNothing);
  });

  testWidgets('wrong-side status asks for the requested face of the ID', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const IdCaptureOverlay(status: LiveIdStatus.wrongSide)),
    );
    expect(find.textContaining('Wrong side'), findsOneWidget);
  });

  testWidgets('capturing replaces the hold-steady prompt', (tester) async {
    await tester.pumpWidget(
      wrap(
        const IdCaptureOverlay(status: LiveIdStatus.aligned, capturing: true),
      ),
    );
    expect(find.text('Capturing…'), findsOneWidget);
  });
}
