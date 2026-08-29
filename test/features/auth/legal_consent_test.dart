import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/auth/data/auth_service.dart';
import 'package:thriftline/features/auth/domain/legal_documents.dart';
import 'package:thriftline/features/auth/presentation/screens/login_screen.dart';
import 'package:thriftline/features/auth/presentation/screens/signup_screen.dart';
import 'package:thriftline/providers/auth_provider.dart';

/// Builds a provider that never reaches Supabase, so the tests below only
/// exercise the client-side consent gate.
Future<AuthProvider> _buildAuthProvider() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferencesService.init();
  return AuthProvider(prefs, AuthService(SupabaseService()));
}

Widget _wrap(Widget child, AuthProvider auth) {
  return MaterialApp(
    home: ChangeNotifierProvider<AuthProvider>.value(value: auth, child: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegalConsent', () {
    test('records both documents against the published version', () {
      final metadata = LegalConsent.now().toMetadata();

      expect(metadata['terms_accepted'], isTrue);
      expect(metadata['privacy_policy_accepted'], isTrue);
      expect(metadata['legal_version'], LegalDocuments.version);
      expect(metadata['legal_accepted_at'], isA<String>());
    });
  });

  group('Consent gate', () {
    testWidgets('signup is blocked until the user agrees', (tester) async {
      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const SignupScreen(), auth));

      await tester.enterText(find.byType(TextFormField).at(0), 'Thrift Fan');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fan@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'sup3rsecret');
      await tester.enterText(find.byType(TextFormField).at(3), 'sup3rsecret');
      await tester.pump();

      await tester.ensureVisible(find.text('Sign Up'));
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('must agree to the Terms and Conditions'),
        findsOneWidget,
      );
      // The gate stops the request before any auth work begins.
      expect(auth.isLoading, isFalse);
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('checkbox starts unchecked and confirms once ticked', (
      tester,
    ) async {
      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const LoginScreen(), auth));

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
      expect(find.textContaining('Consent recorded'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.textContaining('Consent recorded'), findsOneWidget);
    });

    testWidgets('agreeing clears the outstanding consent error', (
      tester,
    ) async {
      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const LoginScreen(), auth));

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'fan@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'sup3rsecret');
      await tester.pump();

      // Distinct from the checkbox's own "You must agree before you can
      // continue." copy, which is always present.
      final errorText = find.textContaining(
        'must agree to the Terms and Conditions',
      );

      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(errorText, findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(errorText, findsNothing);
    });
  });
}
