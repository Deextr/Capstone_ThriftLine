import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/features/auth/data/auth_service.dart';
import 'package:thriftline/features/auth/presentation/screens/signup_screen.dart';
import 'package:thriftline/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Validators.name (signup full name)', () {
    test('accepts common valid names', () {
      const valid = [
        'Juan Dela Cruz',
        'Maria Clara',
        'Anne-Marie Reyes',
        "O'Connor",
        'José García',
        'François Müller',
      ];
      for (final name in valid) {
        expect(Validators.name(name), isNull, reason: name);
      }
    });

    test('requires a non-empty name', () {
      expect(Validators.name(''), Validators.fullNameRequiredMessage);
      expect(Validators.name('   '), Validators.fullNameRequiredMessage);
    });

    test('rejects names shorter than the minimum length', () {
      expect(Validators.name('T'), Validators.fullNameTooShortMessage);
      expect(Validators.name(' T '), Validators.fullNameTooShortMessage);
    });

    test('accepts names at or above the minimum length', () {
      expect(Validators.name('Jo'), isNull);
      expect(Validators.name(' Li '), isNull);
    });

    test('rejects numbers and invalid characters', () {
      const invalid = [
        'Juan Dela Cruz 123!',
        'Juan123',
        'Juan!',
        '123456',
        'Maria@123',
        'An4 Dela Cruz',
        'Maria 😀',
      ];
      for (final name in invalid) {
        expect(
          Validators.name(name),
          Validators.fullNameInvalidMessage,
          reason: name,
        );
      }
    });

    test('normalizeFullName trims and collapses spaces', () {
      expect(
        Validators.normalizeFullName('  Juan   Dela   Cruz  '),
        'Juan Dela Cruz',
      );
    });

    test('accepts hyphens and apostrophes in valid names', () {
      expect(Validators.name('Juan-Dela Cruz'), isNull);
      expect(Validators.name("Juan Dela Cruz O'Neil"), isNull);
    });
  });

  group('SignupScreen full name field', () {
    Future<AuthProvider> buildAuth() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      return AuthProvider(prefs, AuthService(SupabaseService()));
    }

    Widget wrap(AuthProvider auth, Widget child) {
      return MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: child,
        ),
      );
    }

    testWidgets('shows invalid-character message after submit', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = await buildAuth();
      await tester.pumpWidget(wrap(auth, const SignupScreen()));
      await tester.pump();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Juan Dela Cruz 123!',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'user@example.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');

      final signUp = find.text('Sign Up');
      await tester.ensureVisible(signUp);
      await tester.tap(signUp);
      await tester.pump();

      expect(find.text(Validators.fullNameInvalidMessage), findsOneWidget);
    });

    testWidgets('clears invalid-character message after correction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = await buildAuth();
      await tester.pumpWidget(wrap(auth, const SignupScreen()));
      await tester.pump();

      final nameField = find.byType(TextFormField).at(0);
      await tester.enterText(nameField, 'Juan123');
      final signUp = find.text('Sign Up');
      await tester.ensureVisible(signUp);
      await tester.tap(signUp);
      await tester.pump();
      expect(find.text(Validators.fullNameInvalidMessage), findsOneWidget);

      await tester.enterText(nameField, 'Juan Dela Cruz');
      await tester.pump();
      expect(find.text(Validators.fullNameInvalidMessage), findsNothing);
    });
  });
}
