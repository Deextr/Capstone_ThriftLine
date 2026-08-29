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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Consent is never pre-granted: the user must tick the box on every sign-in.
  bool _hasAgreedToLegal = false;
  bool _showConsentError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Blocks the sign-in unless consent has been explicitly given.
  bool _ensureConsent() {
    if (_hasAgreedToLegal) return true;
    setState(() => _showConsentError = true);
    return false;
  }

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_ensureConsent()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      consent: LegalConsent.now(),
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    context.go(auth.homeRoute);
  }

  Future<void> _loginWithGoogle() async {
    if (!_ensureConsent()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.loginWithGoogle(consent: LegalConsent.now());
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    context.go(auth.homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Center(
                    child: Image.asset(
                      'assets/images/thriftline-app-icon.png',
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Thriftline',
                    style: AppTypography.display,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Buy and sell pre-loved fashion',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Email field
                  ThriftTextField(
                    label: 'Email',
                    hint: 'your@email.com',
                    controller: _emailController,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  ThriftTextField(
                    label: 'Password',
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
                  const SizedBox(height: 24),

                  // Terms & Privacy consent gate
                  LegalConsentCheckbox(
                    value: _hasAgreedToLegal,
                    enabled: !auth.isLoading,
                    errorText: _showConsentError
                        ? 'You must agree to the Terms and Conditions and '
                              'Privacy Policy to continue.'
                        : null,
                    onChanged: (value) => setState(() {
                      _hasAgreedToLegal = value;
                      if (value) _showConsentError = false;
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Login button
                  ThriftButton(
                    label: 'Login',
                    onPressed: auth.isLoading ? null : _loginWithEmail,
                    isLoading: auth.isLoading,
                  ),
                  const SizedBox(height: 24),

                  // Divider
                  _OrDivider(),
                  const SizedBox(height: 24),

                  // Google Sign-In button
                  _GoogleSignInButton(
                    onPressed: auth.isLoading ? null : _loginWithGoogle,
                    isLoading: auth.isLoading,
                  ),
                  const SizedBox(height: 24),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: AppTypography.body,
                      ),
                      GestureDetector(
                        onTap: () => context.go(RouteNames.signup),
                        child: Text(
                          'Sign up',
                          style: AppTypography.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared auth widgets
// ─────────────────────────────────────────────────────────────────────────────

/// "or continue with" divider used on both login and signup screens.
class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or continue with',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.3))),
      ],
    );
  }
}

/// Google Sign-In button with the Google logo.
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google "G" logo
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
