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
import '../widgets/auth_branding.dart';
import '../widgets/login_video_background.dart';
import '../widgets/turnstile_challenge.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _turnstileKey = GlobalKey<TurnstileChallengeState>();
  bool _submitted = false;
  bool _emailSent = false;
  String? _turnstileToken;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _clearTurnstile() {
    setState(() => _turnstileToken = null);
    _turnstileKey.currentState?.reset();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final token = _turnstileToken?.trim();
    if (token == null || token.isEmpty) {
      showThriftSnackBar(
        context,
        'Complete human verification before requesting a reset email.',
        isError: true,
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final error = await auth.requestPasswordReset(
      email: _emailController.text.trim(),
      turnstileToken: token,
    );
    if (!mounted) return;
    if (error != null) {
      _clearTurnstile();
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    setState(() => _emailSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 700;
    const fieldLabelColor = Colors.white;
    final canSubmit = !auth.isLoading && (_turnstileToken?.isNotEmpty ?? false);

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
                      onPressed: () => context.go(RouteNames.emailLogin),
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
                              minHeight:
                                  constraints.maxHeight -
                                  (compact ? 4 : AppConstants.spacingSm) -
                                  AppConstants.spacingLg,
                            ),
                            child: _emailSent
                                ? _EmailSentBody(
                                    email: _emailController.text.trim(),
                                    compact: compact,
                                  )
                                : Form(
                                    key: _formKey,
                                    autovalidateMode: _submitted
                                        ? AutovalidateMode.onUserInteraction
                                        : AutovalidateMode.disabled,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Center(
                                          child: AuthBrandLogo(
                                            size: compact ? 72 : 84,
                                          ),
                                        ),
                                        SizedBox(height: compact ? 12 : 16),
                                        Text(
                                          'Forgot password',
                                          style: AppTypography.heading.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Enter the email you used for ThriftLine. '
                                          'We will send you a secure link to choose a new password.',
                                          style: AppTypography.body.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: compact ? 24 : 32),
                                        ThriftTextField(
                                          label: 'Email',
                                          hint: 'your@email.com',
                                          controller: _emailController,
                                          icon: Icons.email_outlined,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          validator: Validators.email,
                                          labelColor: fieldLabelColor,
                                        ),
                                        const SizedBox(height: 16),
                                        TurnstileChallenge(
                                          key: _turnstileKey,
                                          action: 'password_reset',
                                          onToken: (token) => setState(
                                            () => _turnstileToken = token,
                                          ),
                                          onError: (_) => setState(
                                            () => _turnstileToken = null,
                                          ),
                                          onExpired: () => setState(
                                            () => _turnstileToken = null,
                                          ),
                                        ),
                                        SizedBox(height: compact ? 20 : 24),
                                        ThriftButton(
                                          label: 'Send reset link',
                                          onPressed: canSubmit ? _submit : null,
                                          isLoading: auth.isLoading,
                                        ),
                                        const SizedBox(height: 20),
                                        GestureDetector(
                                          onTap: () =>
                                              context.go(RouteNames.emailLogin),
                                          child: Text(
                                            'Back to login',
                                            style: AppTypography.body.copyWith(
                                              color: AppColors.primaryLight,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
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

class _EmailSentBody extends StatelessWidget {
  const _EmailSentBody({required this.email, required this.compact});

  final String email;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Container(
            width: compact ? 64 : 72,
            height: compact ? 64 : 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryLight),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        SizedBox(height: compact ? 20 : 28),
        Text(
          'Check your email',
          style: AppTypography.heading.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'If an email and password account exists for $email, you will receive '
          'a password reset link shortly. Open it on this device to choose a '
          'new password. If you created your account with Continue with Google, '
          'sign in with Google instead.',
          style: AppTypography.body.copyWith(
            color: Colors.white.withValues(alpha: 0.82),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: compact ? 28 : 36),
        ThriftButton(
          label: 'Back to login',
          onPressed: () => context.go(RouteNames.login),
        ),
      ],
    );
  }
}
