import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/features/auth/data/auth_service.dart';
import 'package:thriftline/features/profile/widgets/edit_profile_form.dart';
import 'package:thriftline/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditProfileForm buyer full name', () {
    Future<AuthProvider> buildAuth() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();
      return AuthProvider(prefs, AuthService(SupabaseService()));
    }

    Widget wrap(AuthProvider auth, Widget child) {
      return MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: Scaffold(body: child),
        ),
      );
    }

    EditProfileForm buildForm({
      required Future<void> Function({
        required String fullName,
        required String username,
        required String phone,
      })
      onSave,
    }) {
      return EditProfileForm(
        initialName: 'Juan Dela Cruz',
        initialUsername: 'juancruz',
        initialEmail: 'juan@example.com',
        initialPhone: '',
        isSaving: false,
        isSellerMode: false,
        canChangeEmail: false,
        onSave: onSave,
      );
    }

    testWidgets('rejects one-character full name on save', (tester) async {
      var saveCalled = false;
      final auth = await buildAuth();
      await tester.pumpWidget(
        wrap(
          auth,
          buildForm(
            onSave:
                ({required fullName, required username, required phone}) async {
                  saveCalled = true;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'T');
      await tester.tap(find.text('Save changes'));
      await tester.pump();

      expect(saveCalled, isFalse);
      expect(find.text(Validators.fullNameTooShortMessage), findsOneWidget);
    });

    testWidgets('accepts full name at minimum length and calls onSave', (
      tester,
    ) async {
      var savedName = '';
      final auth = await buildAuth();
      await tester.pumpWidget(
        wrap(
          auth,
          buildForm(
            onSave:
                ({required fullName, required username, required phone}) async {
                  savedName = fullName;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Jo');
      await tester.tap(find.text('Save changes'));
      await tester.pump();

      expect(savedName, 'Jo');
    });
  });
}
