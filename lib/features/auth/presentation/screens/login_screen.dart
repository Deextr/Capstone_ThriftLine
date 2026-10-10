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
import '../../domain/login_rate_limiter.dart';
import '../widgets/auth_branding.dart' show AuthVideoScrim;
import '../widgets/auth_lockout_banner.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/legal_consent_notice.dart';
import '../widgets/login_video_background.dart';
import '../widgets/turnstile_challenge.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _turnstileKey = GlobalKey<TurnstileChallengeState>();

  bool _showEmailSignIn = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  String? _turnstileToken;

  final LoginRateLimiter _rateLimiter = LoginRateLimiter();

  @override
  void initState() {
    super.initState();
    _rateLimiter.addListener(_onRateLimiterChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final openEmail =
        GoRouterState.of(context).uri.queryParameters['email'] == '1';
    if (openEmail && !_showEmailSignIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showEmailSignIn = true);
      });
    }
  }

  @override
  void dispose() {
    _rateLimiter.removeListener(_onRateLimiterChanged);
    _rateLimiter.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRateLimiterChanged() {
    if (mounted) setState(() {});
  }

  void _openEmailSignIn() {
    FocusScope.of(context).unfocus();
    setState(() => _showEmailSignIn = true);
  }

  void _closeEmailSignIn() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showEmailSignIn = false;
      _submitted = false;
      _turnstileToken = null;
    });
    _turnstileKey.currentState?.reset();
  }

  void _clearTurnstile() {
    setState(() => _turnstileToken = null);
    _turnstileKey.currentState?.reset();
  }

  Future<void> _loginWithEmail() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    if (_rateLimiter.isLockedOut) {
      showThriftSnackBar(context, _rateLimiter.lockoutMessage, isError: true);
      return;
    }

    final token = _turnstileToken?.trim();
    if (token == null || token.isEmpty) {
      showThriftSnackBar(
        context,
        'Complete human verification before signing in.',
        isError: true,
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final loginResult = await auth.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      consent: LegalConsent.now(),
      turnstileToken: token,
    );
    if (!mounted) return;
    if (!loginResult.isSuccess) {
      _rateLimiter.recordFailure();
      _clearTurnstile();
      showThriftSnackBar(context, loginResult.errorMessage!, isError: true);
      return;
    }

    _rateLimiter.recordSuccess();
    context.go(
      auth.isEmailOtpPending ? RouteNames.verifyEmailOtp : auth.homeRoute,
    );
  }

  Future<void> _loginWithGoogle() async {
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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 700;
    const fieldLabelColor = Colors.white;
    final lockedOut = _rateLimiter.isLockedOut;

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
              child: Selector<AuthProvider, bool>(
                selector: (_, auth) => auth.isLoading,
                builder: (context, isLoading, _) {
                  final canSubmitEmail =
                      !isLoading &&
                      !lockedOut &&
                      (_turnstileToken?.isNotEmpty ?? false);
                  return Column(
                    children: [
                      if (_showEmailSignIn)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: isLoading ? null : _closeEmailSignIn,
                          ),
                        ),
                      Expanded(
                        child: _showEmailSignIn
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    padding: EdgeInsets.fromLTRB(
                                      AppConstants.spacingLg,
                                      compact ? 4 : AppConstants.spacingSm,
                                      AppConstants.spacingLg,
                                      AppConstants.spacingMd,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: _EmailSignInBody(
                                        formKey: _formKey,
                                        compact: compact,
                                        lockedOut: lockedOut,
                                        isLoading: isLoading,
                                        canSubmitEmail: canSubmitEmail,
                                        emailController: _emailController,
                                        passwordController: _passwordController,
                                        obscurePassword: _obscurePassword,
                                        submitted: _submitted,
                                        rateLimiter: _rateLimiter,
                                        turnstileKey: _turnstileKey,
                                        onObscureToggle: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        onTurnstileToken: (token) => setState(
                                          () => _turnstileToken = token,
                                        ),
                                        onTurnstileClear: () => setState(
                                          () => _turnstileToken = null,
                                        ),
                                        onSignIn: _loginWithEmail,
                                        fieldLabelColor: fieldLabelColor,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : _AuthMethodPicker(
                                isLoading: isLoading,
                                onGoogle: _loginWithGoogle,
                                onEmail: _openEmailSignIn,
                              ),
                      ),
                      if (_showEmailSignIn)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.spacingLg,
                            AppConstants.spacingSm,
                            AppConstants.spacingLg,
                            AppConstants.spacingMd,
                          ),
                          child: const LegalConsentNotice(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthMethodPicker extends StatelessWidget {
  const _AuthMethodPicker({
    required this.isLoading,
    required this.onGoogle,
    required this.onEmail,
  });

  final bool isLoading;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingLg,
        0,
        AppConstants.spacingLg,
        48,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          GoogleSignInButton(
            onPressed: isLoading ? null : onGoogle,
            isLoading: isLoading,
          ),
          const SizedBox(height: 16),
          const _OrDivider(),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Continue with Email',
            onPressed: isLoading ? null : onEmail,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: AppTypography.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              GestureDetector(
                onTap: () => context.go(RouteNames.signup),
                child: Text(
                  'Sign Up',
                  style: AppTypography.body.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const LegalConsentNotice(),
        ],
      ),
    );
  }
}

class _EmailSignInBody extends StatelessWidget {
  const _EmailSignInBody({
    required this.formKey,
    required this.compact,
    required this.lockedOut,
    required this.isLoading,
    required this.canSubmitEmail,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.submitted,
    required this.rateLimiter,
    required this.turnstileKey,
    required this.onObscureToggle,
    required this.onTurnstileToken,
    required this.onTurnstileClear,
    required this.onSignIn,
    required this.fieldLabelColor,
  });

  final GlobalKey<FormState> formKey;
  final bool compact;
  final bool lockedOut;
  final bool isLoading;
  final bool canSubmitEmail;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool submitted;
  final LoginRateLimiter rateLimiter;
  final GlobalKey<TurnstileChallengeState> turnstileKey;
  final VoidCallback onObscureToggle;
  final ValueChanged<String> onTurnstileToken;
  final VoidCallback onTurnstileClear;
  final Future<void> Function() onSignIn;
  final Color fieldLabelColor;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sign in with Email',
            style: AppTypography.heading.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: compact ? 20 : 28),
          if (lockedOut) ...[
            AuthLockoutBanner(message: rateLimiter.lockoutMessage),
            const SizedBox(height: 16),
          ],
          ThriftTextField(
            label: 'Email',
            hint: 'your@email.com',
            controller: emailController,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
            labelColor: fieldLabelColor,
          ),
          const SizedBox(height: 16),
          ThriftTextField(
            label: 'Password',
            controller: passwordController,
            obscureText: obscurePassword,
            icon: Icons.lock_outline,
            validator: Validators.password,
            labelColor: fieldLabelColor,
            suffix: IconButton(
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onObscureToggle,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: lockedOut || isLoading
                  ? null
                  : () => context.go(RouteNames.forgotPassword),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
              ),
              child: Text(
                'Forgot password?',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TurnstileChallenge(
            key: turnstileKey,
            action: 'login',
            onToken: onTurnstileToken,
            onError: (_) => onTurnstileClear(),
            onExpired: onTurnstileClear,
          ),
          SizedBox(height: compact ? 16 : 20),
          ThriftButton(
            label: lockedOut ? 'Locked' : 'Sign In',
            onPressed: canSubmitEmail ? onSignIn : null,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Colors.white.withValues(alpha: 0.28);
    return Row(
      children: [
        Expanded(child: Divider(color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        Expanded(child: Divider(color: line)),
      ],
    );
  }
}
