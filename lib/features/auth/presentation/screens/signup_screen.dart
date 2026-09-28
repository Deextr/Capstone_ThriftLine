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
import '../widgets/auth_branding.dart';
import '../widgets/legal_consent_notice.dart';
import '../widgets/login_video_background.dart';

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
  String? _errorMessage;

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

    setState(() => _errorMessage = null);

    final auth = context.read<AuthProvider>();
    final result = await auth.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      consent: LegalConsent.now(),
    );
    if (!mounted) return;
    if (!result.success) {
      final message =
          result.errorMessage ?? 'Something went wrong. Please try again.';
      setState(() => _errorMessage = message);
      showThriftSnackBar(context, message, isError: true);
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

    if (result.requiresEmailOtp || auth.isEmailOtpPending) {
      context.go(RouteNames.verifyEmailOtp);
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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 700;
    const fieldLabelColor = Colors.white;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LoginVideoBackground(),
            const AuthVideoScrim(),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.go(RouteNames.login),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            AppConstants.spacingLg,
                            compact ? 4 : AppConstants.spacingSm,
                            AppConstants.spacingLg,
                            AppConstants.spacingLg,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight -
                                  (compact ? 4 : AppConstants.spacingSm) -
                                  AppConstants.spacingLg,
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Center(
                                    child: AuthBrandLogo(
                                      size: compact ? 72 : 84,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 12 : 16),
                                  Text(
                                    'ThriftLine',
                                    style: AppTypography.display.copyWith(
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0x66000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Create Account',
                                    style: AppTypography.heading.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Join ThriftLine and start selling or shopping today.',
                                    style: AppTypography.body.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: compact ? 20 : 28),
                                  ThriftTextField(
                                    label: 'Full Name',
                                    hint: 'Enter your full name',
                                    controller: _nameController,
                                    icon: Icons.person_outline,
                                    validator: Validators.name,
                                    labelColor: fieldLabelColor,
                                  ),
                                  const SizedBox(height: 16),
                                  ThriftTextField(
                                    label: 'Email Address',
                                    hint: 'Enter your email address',
                                    controller: _emailController,
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: Validators.email,
                                    labelColor: fieldLabelColor,
                                  ),
                                  const SizedBox(height: 16),
                                  ThriftTextField(
                                    label: 'Password',
                                    hint: 'Create a password',
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    icon: Icons.lock_outline,
                                    validator: Validators.password,
                                    labelColor: fieldLabelColor,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
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
                                    labelColor: fieldLabelColor,
                                  ),
                                  SizedBox(height: compact ? 20 : 24),
                                  if (_errorMessage != null) ...[
                                    Text(
                                      _errorMessage!,
                                      style: AppTypography.body.copyWith(
                                        color: const Color(0xFFFECACA),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: compact ? 12 : 16),
                                  ],
                                  ThriftButton(
                                    label: 'Sign Up',
                                    onPressed: auth.isLoading
                                        ? null
                                        : _signUpWithEmail,
                                    isLoading: auth.isLoading,
                                  ),
                                  SizedBox(height: compact ? 16 : 20),
                                  const LegalConsentNotice(),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Already have an account? ',
                                        style: AppTypography.body.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            context.go(RouteNames.login),
                                        child: Text(
                                          'Log In',
                                          style: AppTypography.body.copyWith(
                                            color: AppColors.primaryLight,
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
