import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void thriftTextFieldWidgetTests() {
  qaGroup('ThriftTextField', () {
    qaWidgetTest('shows label, hint and error text', (tester) async {
      await tester.pumpWidget(
        _host(
          const ThriftTextField(
            label: 'Email',
            hint: 'you@example.com',
            error: 'Please enter a valid email address.',
          ),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('you@example.com'), findsOneWidget);
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });

    qaWidgetTest('typing updates the controller and onChanged', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;

      await tester.pumpWidget(
        _host(
          ThriftTextField(
            controller: controller,
            onChanged: (value) => changed = value,
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'denim jacket');
      expect(controller.text, 'denim jacket');
      expect(changed, 'denim jacket');
    });

    qaWidgetTest('obscureText hides password input', (tester) async {
      await tester.pumpWidget(
        _host(const ThriftTextField(label: 'Password', obscureText: true)),
      );

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.obscureText, isTrue);
    });

    qaWidgetTest('maxLength is enforced and counter hidden', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(ThriftTextField(controller: controller, maxLength: 5)),
      );

      await tester.enterText(find.byType(TextFormField), 'abcdefgh');
      await tester.pump();
      expect(controller.text, 'abcde');
      expect(find.text('5/5'), findsNothing);
    });

    qaWidgetTest('validator errors appear when the form validates', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        _host(
          Form(
            key: formKey,
            child: const ThriftTextField(
              label: 'Email',
              validator: Validators.email,
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Please enter your email address.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'buyer@thrift.ph');
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Please enter your email address.'), findsNothing);
    });
  });
}
