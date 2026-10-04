import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// A minimal sign-in screen assembled only from production widgets and
/// validators. It checks that the shared building blocks work together as a
/// screen without needing Supabase, routing or providers.
class _SignInHarness extends StatefulWidget {
  const _SignInHarness({required this.onSubmit});

  final void Function(String email, String password) onSubmit;

  @override
  State<_SignInHarness> createState() => _SignInHarnessState();
}

class _SignInHarnessState extends State<_SignInHarness> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onSubmit(_email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              ThriftTextField(
                key: const Key('qa-email'),
                label: 'Email',
                controller: _email,
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('qa-password'),
                label: 'Password',
                controller: _password,
                obscureText: true,
                validator: Validators.password,
              ),
              const SizedBox(height: 24),
              ThriftButton(label: 'Sign in', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _field(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);

void signInScreenWidgetTests() {
  qaGroup('Sign-in screen (widget composition)', () {
    qaWidgetTest('empty submit shows both validation errors', (tester) async {
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(home: _SignInHarness(onSubmit: (_, _) => submitted = true)),
      );

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Please enter your email address.'), findsOneWidget);
      expect(find.text('Please enter a password.'), findsOneWidget);
      expect(submitted, isFalse);
    });

    qaWidgetTest('invalid email and short password are rejected', (
      tester,
    ) async {
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(home: _SignInHarness(onSubmit: (_, _) => submitted = true)),
      );

      await tester.enterText(_field('qa-email'), 'buyer@thriftline');
      await tester.enterText(_field('qa-password'), '123');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 6 characters.'),
        findsOneWidget,
      );
      expect(submitted, isFalse);
    });

    qaWidgetTest('valid input submits trimmed credentials', (tester) async {
      String? email;
      String? password;
      await tester.pumpWidget(
        MaterialApp(
          home: _SignInHarness(
            onSubmit: (e, p) {
              email = e;
              password = p;
            },
          ),
        ),
      );

      await tester.enterText(_field('qa-email'), '  buyer@thrift.ph ');
      await tester.enterText(_field('qa-password'), 'secret123');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(email, 'buyer@thrift.ph');
      expect(password, 'secret123');
      expect(find.text('Please enter a valid email address.'), findsNothing);
    });

    qaWidgetTest('layout fits a small 320px phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: _SignInHarness(onSubmit: (_, _) {})),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });
}
