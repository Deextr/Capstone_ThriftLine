import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/widgets/keyboard_safe.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required Size size,
  required double keyboard,
}) async {
  // Match Android adjustResize: the window shrinks; do not also pad insets.
  tester.view.physicalSize = Size(size.width, size.height - keyboard);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: KeyboardSafeSheet(
            action: ThriftButton(label: 'Save GCash', onPressed: () {}),
            children: [
              for (var index = 0; index < 8; index++) ...[
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Field $index',
                    errorText: index == 1 ? 'Enter a valid number.' : null,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final size in const [Size(320, 568), Size(430, 932)]) {
    testWidgets('save stays above the keyboard on ${size.width.toInt()}px', (
      tester,
    ) async {
      const keyboard = 280.0;
      await _pumpSheet(tester, size: size, keyboard: keyboard);

      expect(tester.takeException(), isNull);
      expect(find.text('Save GCash'), findsOneWidget);
      expect(find.text('Enter a valid number.'), findsOneWidget);

      final button = tester.getRect(find.text('Save GCash'));
      expect(button.bottom, lessThanOrEqualTo(size.height - keyboard + 1));
      expect(button.top, greaterThanOrEqualTo(0));
    });
  }
}
