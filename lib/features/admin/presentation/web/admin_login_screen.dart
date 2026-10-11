import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart' show Validators;
import '../../../auth/config/turnstile_config.dart';
import '../../../auth/domain/auth_error.dart';
import '../../../auth/domain/legal_documents.dart';
import '../../../auth/domain/login_portal.dart';
import '../../../auth/presentation/widgets/turnstile_challenge.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _turnstileKey = GlobalKey<TurnstileChallengeState>();

  bool _obscure = true;
  bool _busy = false;
  bool _submitted = false;
  String? _error;
  String? _turnstileToken;
  int? _lockoutSecondsRemaining;
  Timer? _lockoutTimer;

  static const _turnstileAction = 'login';

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _turnstileReady =>
      !TurnstileConfig.isConfigured ||
      (_turnstileToken != null && _turnstileToken!.isNotEmpty);

  bool get _canSubmit =>
      !_busy && _turnstileReady && (_lockoutSecondsRemaining ?? 0) <= 0;

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    final clamped = seconds.clamp(1, 86400);
    setState(() => _lockoutSecondsRemaining = clamped);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _lockoutSecondsRemaining;
      if (remaining == null || remaining <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSecondsRemaining = null;
          if (_error != null &&
              _error!.startsWith('Too many failed login attempts')) {
            _error = null;
          }
        });
        return;
      }
      setState(() {
        _lockoutSecondsRemaining = remaining - 1;
        _error = adminLoginLockoutMessage(remaining - 1);
      });
    });
  }

  void _onTurnstileToken(String token) {
    setState(() {
      _turnstileToken = token;
      if (_error == 'Complete the security verification before signing in.') {
        _error = null;
      }
    });
  }

  void _onTurnstileError() {
    setState(() => _turnstileToken = null);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (TurnstileConfig.isConfigured &&
        (_turnstileToken == null || _turnstileToken!.isEmpty)) {
      setState(() {
        _error = 'Complete the security verification before signing in.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    try {
      final loginResult = await auth.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        consent: LegalConsent.now(),
        turnstileToken: _turnstileToken ?? '',
        loginPortal: LoginPortal.admin,
      );
      if (!mounted) return;
      if (!loginResult.isSuccess) {
        final retry = loginResult.retryAfterSeconds;
        setState(() {
          _error = loginResult.errorMessage;
          _turnstileToken = null;
        });
        if (retry != null) {
          _startLockoutCountdown(retry);
        } else {
          await _turnstileKey.currentState?.reset();
        }
        return;
      }
      _lockoutTimer?.cancel();
      setState(() => _lockoutSecondsRemaining = null);
      if (!auth.canUseAdminPortal) {
        final deactivated = auth.isDeactivatedAdministrator;
        await auth.logout();
        if (mounted) {
          context.go(
            deactivated
                ? '${RouteNames.adminAccessDenied}?reason=deactivated'
                : RouteNames.adminAccessDenied,
          );
        }
        return;
      }
      if (auth.isEmailOtpPending) {
        if (mounted) context.go(RouteNames.adminVerifyEmailOtp);
        return;
      }
      final redirect = GoRouterState.of(
        context,
      ).uri.queryParameters['redirect'];
      if (redirect != null && redirect.startsWith('/admin')) {
        context.go(Uri.decodeComponent(redirect));
      } else {
        context.go(RouteNames.adminDashboard);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to sign in. Check your email and password.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppConstants.breakpointTablet;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ScrollConfiguration(
            behavior: const _AdminLoginScrollBehavior(),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 20 : 32,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 440 : 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 24 : 32,
                      32,
                      compact ? 24 : 32,
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(compact: compact),
                        const SizedBox(height: 28),
                        if (_error != null) ...[
                          _ErrorBanner(message: _error!),
                          const SizedBox(height: 20),
                        ],
                        Form(
                          key: _formKey,
                          autovalidateMode: _submitted
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                focusNode: _emailFocus,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: _fieldDecoration(
                                  label: 'Email',
                                  hint: 'admin@example.com',
                                ),
                                validator: Validators.email,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                enabled: !_busy,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                decoration: _fieldDecoration(
                                  label: 'Password',
                                  suffix: IconButton(
                                    tooltip: _obscure
                                        ? 'Show password'
                                        : 'Hide password',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Enter your password'
                                    : null,
                                onFieldSubmitted: (_) {
                                  if (_canSubmit) _submit();
                                },
                              ),
                            ],
                          ),
                        ),
                        if (TurnstileConfig.isConfigured) ...[
                          const SizedBox(height: 24),
                          TurnstileChallenge(
                            key: _turnstileKey,
                            action: _turnstileAction,
                            appearance: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? TurnstileChallengeAppearance.darkOverlay
                                : TurnstileChallengeAppearance.lightSurface,
                            showSuccessMessage: false,
                            showLoadingMessage: false,
                            onToken: _onTurnstileToken,
                            onError: (_) => _onTurnstileError(),
                            onExpired: _onTurnstileError,
                          ),
                        ],
                        const SizedBox(height: 28),
                        ThriftButton(
                          label: _busy ? 'Signing in…' : 'Sign in',
                          onPressed: _canSubmit ? _submit : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      suffixIcon: suffix,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/thriftline_revised_app_logo.jpg',
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              color: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(
                Icons.storefront_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ThriftLine',
          style: AppTypography.heading.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Administration Portal',
          style: AppTypography.subheading.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 10),
        Text(
          'Sign in with your administrator account. '
          'Buyer and seller accounts cannot access this workspace.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Hides scrollbars on the admin login page (including Flutter Web).
class _AdminLoginScrollBehavior extends MaterialScrollBehavior {
  const _AdminLoginScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
