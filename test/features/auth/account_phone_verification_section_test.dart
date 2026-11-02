import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/auth/presentation/widgets/account_phone_verification_section.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/providers/auth_provider.dart';

class _VerifiedPhoneAuth extends Fake
    with ChangeNotifier
    implements AuthProvider {
  _VerifiedPhoneAuth(this._user);

  final AuthUser _user;

  @override
  AuthUser? get user => _user;
}

void main() {
  testWidgets('locks verified phone field during seller registration', (
    tester,
  ) async {
    const phone = '09171234567';
    final controller = TextEditingController(text: phone);
    addTearDown(controller.dispose);

    final auth = _VerifiedPhoneAuth(
      const AuthUser(
        id: 'u1',
        username: 'buyer',
        name: 'Buyer',
        email: 'b@test.com',
        phone: phone,
        isPhoneVerified: true,
        role: UserRole.buyer,
        avatarUrl: '',
        location: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: AccountPhoneVerificationSection(
              phoneController: controller,
              lockVerifiedPhone: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).readOnly,
      isTrue,
    );
    expect(find.text('Change'), findsNothing);
    expect(
      find.text('This number is verified and locked for seller registration.'),
      findsOneWidget,
    );
  });
}
