import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/constants/app_constants.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/utils/ph_phone.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Full interactive authentication harness representing the end-to-end signup flow.
class _AuthSignUpIntegrationFlow extends StatefulWidget {
  const _AuthSignUpIntegrationFlow({required this.onSuccess});

  final void Function({
    required String name,
    required String email,
    required String phone,
    required UserRole role,
  })
  onSuccess;

  @override
  State<_AuthSignUpIntegrationFlow> createState() =>
      _AuthSignUpIntegrationFlowState();
}

class _AuthSignUpIntegrationFlowState
    extends State<_AuthSignUpIntegrationFlow> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  UserRole _selectedRole = UserRole.buyer;
  bool _termsAccepted = false;
  String? _termsError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() {
      _termsError =
          _termsAccepted ? null : 'You must accept the Terms and Conditions.';
    });

    if (_formKey.currentState!.validate() && _termsAccepted) {
      widget.onSuccess(
        name: Validators.normalizeFullName(_nameController.text),
        email: _emailController.text.trim(),
        phone: normalizePhMobile(_phoneController.text)!,
        role: _selectedRole,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ThriftLine Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThriftTextField(
                key: const Key('auth-name-field'),
                label: 'Full Name',
                controller: _nameController,
                validator: Validators.name,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('auth-email-field'),
                label: 'Email',
                controller: _emailController,
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('auth-phone-field'),
                label: 'Mobile Number',
                controller: _phoneController,
                validator: phMobileValidationError,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('auth-password-field'),
                label: 'Password',
                controller: _passwordController,
                obscureText: true,
                validator: Validators.password,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('auth-confirm-password-field'),
                label: 'Confirm Password',
                controller: _confirmPasswordController,
                obscureText: true,
                validator:
                    (v) => Validators.confirmPassword(
                      v,
                      _passwordController.text,
                    ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Account Type:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    key: const Key('auth-role-buyer'),
                    label: const Text('Buyer'),
                    selected: _selectedRole == UserRole.buyer,
                    onSelected: (_) => setState(() => _selectedRole = UserRole.buyer),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    key: const Key('auth-role-seller'),
                    label: const Text('Seller'),
                    selected: _selectedRole == UserRole.seller,
                    onSelected: (_) => setState(() => _selectedRole = UserRole.seller),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    key: const Key('auth-terms-checkbox'),
                    value: _termsAccepted,
                    onChanged:
                        (val) => setState(() {
                          _termsAccepted = val ?? false;
                          if (_termsAccepted) _termsError = null;
                        }),
                  ),
                  const Expanded(
                    child: Text('I agree to the ThriftLine Terms and Conditions'),
                  ),
                ],
              ),
              if (_termsError != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Text(
                    _termsError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
              ThriftButton(
                key: const Key('auth-submit-button'),
                label: 'Register Account',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _fieldInput(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);

void authIntegrationTests() {
  qaGroup('Authentication Integration Flow', () {
    qaIntegrationTest('full sign-up registration with validation & role assignment', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      String? registeredName;
      String? registeredEmail;
      String? registeredPhone;
      UserRole? registeredRole;

      await tester.pumpWidget(
        MaterialApp(
          home: _AuthSignUpIntegrationFlow(
            onSuccess: ({required name, required email, required phone, required role}) {
              registeredName = name;
              registeredEmail = email;
              registeredPhone = phone;
              registeredRole = role;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial attempt without filling anything
      await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text(Validators.fullNameRequiredMessage), findsOneWidget);
      expect(find.text('Please enter your email address.'), findsOneWidget);
      expect(find.text('Please enter a valid phone number.'), findsOneWidget);
      expect(find.text('Please enter a password.'), findsOneWidget);
      expect(
        find.text('You must accept the Terms and Conditions.'),
        findsOneWidget,
      );
      expect(registeredName, isNull);

      // 2. Fill invalid details
      await tester.enterText(_fieldInput('auth-name-field'), 'John123');
      await tester.enterText(_fieldInput('auth-email-field'), 'not-an-email');
      await tester.enterText(_fieldInput('auth-phone-field'), '08123456789'); // invalid PH prefix
      await tester.enterText(_fieldInput('auth-password-field'), '123');
      await tester.enterText(_fieldInput('auth-confirm-password-field'), '456');

      await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text(Validators.fullNameInvalidMessage), findsOneWidget);
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters.'), findsOneWidget);
      expect(find.text('Passwords do not match.'), findsOneWidget);

      // 3. Fill valid details and switch role to Seller
      await tester.enterText(_fieldInput('auth-name-field'), '  Dexter   Ramos  ');
      await tester.enterText(_fieldInput('auth-email-field'), 'dexter@thriftline.ph');
      await tester.enterText(_fieldInput('auth-phone-field'), '+63 917 123 4567');
      await tester.enterText(_fieldInput('auth-password-field'), 'secret123');
      await tester.enterText(_fieldInput('auth-confirm-password-field'), 'secret123');

      // Select Seller role
      await tester.ensureVisible(find.byKey(const Key('auth-role-seller')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-role-seller')));
      await tester.pumpAndSettle();

      // Accept terms
      await tester.ensureVisible(find.byKey(const Key('auth-terms-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-terms-checkbox')));
      await tester.pumpAndSettle();

      // Submit valid form
      await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();

      expect(registeredName, 'Dexter Ramos');
      expect(registeredEmail, 'dexter@thriftline.ph');
      expect(registeredPhone, '09171234567');
      expect(registeredRole, UserRole.seller);

      // 4. Verify auth session persistence in SharedPreferencesService
      await prefs.setLoggedIn(true);
      await prefs.setUserId('user-dex-123');
      await prefs.setUsername('dexter_r');
      await prefs.setDisplayName(registeredName!);
      await prefs.setUserRole(registeredRole!.name);
      await prefs.setActiveAccount(userId: 'user-dex-123', mode: 'seller');

      expect(prefs.isLoggedIn, isTrue);
      expect(prefs.userId, 'user-dex-123');
      expect(prefs.displayName, 'Dexter Ramos');
      expect(prefs.userRole, 'seller');
      expect(prefs.activeAccountFor('user-dex-123'), 'seller');
    });

    qaIntegrationTest('session logout clears user credentials but preserves trusted device install marker', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      await prefs.setLoggedIn(true);
      await prefs.setUserId('user-qa-999');
      await prefs.setUserRole('seller');
      await prefs.setDeviceTrustInstallId('device-trust-uuid-999');

      expect(prefs.isLoggedIn, isTrue);
      expect(prefs.deviceTrustInstallId, 'device-trust-uuid-999');

      // Execute session logout
      await prefs.clearAuthSession();

      expect(prefs.isLoggedIn, isFalse);
      expect(prefs.userId, isNull);
      expect(prefs.userRole, isNull);
      // Security rule: device trust marker survives logout
      expect(prefs.deviceTrustInstallId, 'device-trust-uuid-999');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    authIntegrationTests();
  });
}
