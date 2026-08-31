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
    testWidgets('signup shows a text notice instead of a consent checkbox', (
      tester,
    ) async {
      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const SignupScreen(), auth));
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('ThriftLine'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(
        find.textContaining('By continuing, you agree'),
        findsOneWidget,
      );
      expect(find.textContaining('Terms and Conditions'), findsOneWidget);
      expect(find.textContaining('Privacy Policy'), findsOneWidget);
    });

    testWidgets('signup fits a compact Android phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const SignupScreen(), auth));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('login shows a text notice instead of a consent checkbox', (
      tester,
    ) async {
      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const LoginScreen(), auth));
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('ThriftLine'), findsOneWidget);
      expect(
        find.textContaining('By continuing, you agree'),
        findsOneWidget,
      );
      expect(find.textContaining('Terms and Conditions'), findsOneWidget);
      expect(find.textContaining('Privacy Policy'), findsOneWidget);
    });

    testWidgets('login fits a compact Android phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = await _buildAuthProvider();
      await tester.pumpWidget(_wrap(const LoginScreen(), auth));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });
  });
}
