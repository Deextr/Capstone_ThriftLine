import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/legal_documents.dart';
import '../widgets/legal_consent_checkbox.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;

  // Consent starts unchecked and must be given before registration proceeds.
  bool _hasAgreedToLegal = false;
  bool _showConsentError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasAgreedToLegal) {
      setState(() => _showConsentError = true);
      return;
    }

    final auth = context.read<AuthProvider>();
    final result = await auth.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      consent: LegalConsent.now(),
    );
    if (!mounted) return;
    if (!result.success) {
      showThriftSnackBar(
        context,
        result.errorMessage ?? 'Something went wrong. Please try again.',
        isError: true,
      );
      return;
    }

    if (result.requiresEmailVerification) {
      showThriftSnackBar(
        context,
        'Account created! Please check your email to verify your account.',
      );
      context.go(RouteNames.login);
      return;
    }

    context.go(auth.homeRoute);
  }

  String? _confirmPasswordValidator(String? value) {
    final confirmPassword = value?.trim() ?? '';
    if (confirmPassword.isEmpty) {
      return 'Passwords do not match.';
    }
    if (confirmPassword != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(RouteNames.login),
            style: IconButton.styleFrom(backgroundColor: Colors.transparent),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/thriftline-app-icon.png',
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create Account',
                    style: AppTypography.display,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join ThriftLine and start selling or shopping today.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  ThriftTextField(
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    controller: _nameController,
                    icon: Icons.person_outline,
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Email Address',
                    hint: 'Enter your email address',
                    controller: _emailController,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Password',
                    hint: 'Create a password',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    icon: Icons.lock_outline,
                    validator: Validators.password,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Confirm Password',
                    hint: 'Confirm your password',
                    controller: _confirmPasswordController,
                    obscureText: _obscurePassword,
                    icon: Icons.lock_reset_outlined,
                    validator: _confirmPasswordValidator,
                  ),
                  const SizedBox(height: 24),
                  LegalConsentCheckbox(
                    value: _hasAgreedToLegal,
                    enabled: !auth.isLoading,
                    errorText: _showConsentError
                        ? 'You must agree to the Terms and Conditions and '
                              'Privacy Policy to create an account.'
                        : null,
                    onChanged: (value) => setState(() {
                      _hasAgreedToLegal = value;
                      if (value) _showConsentError = false;
                    }),
                  ),
                  const SizedBox(height: 24),
                  ThriftButton(
                    label: 'Sign Up',
                    onPressed: auth.isLoading ? null : _signUpWithEmail,
                    isLoading: auth.isLoading,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: AppTypography.body,
                      ),
                      GestureDetector(
                        onTap: () => context.go(RouteNames.login),
                        child: Text(
                          'Log In',
                          style: AppTypography.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
