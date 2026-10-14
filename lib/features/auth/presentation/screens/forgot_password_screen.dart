import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart';
import '../../domain/auth_error.dart';
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
                      onPressed: _emailSent
                          ? () => context.go(RouteNames.login)
                          : () => context.go(RouteNames.emailLogin),
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
                            AppConstants.spacingMd,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  constraints.maxHeight -
                                  (compact ? 4 : AppConstants.spacingSm),
                            ),
                            child: IndexedStack(
                              index: _emailSent ? 1 : 0,
                              sizing: StackFit.loose,
                              children: [
                                Selector<AuthProvider, bool>(
                                  selector: (_, auth) => auth.isLoading,
                                  builder: (context, isLoading, _) {
                                    final canSubmit = !isLoading &&
                                        (_turnstileToken?.isNotEmpty ?? false);
                                    return _ForgotPasswordForm(
                                      formKey: _formKey,
                                      compact: compact,
                                      submitted: _submitted,
                                      emailController: _emailController,
                                      turnstileKey: _turnstileKey,
                                      fieldLabelColor: fieldLabelColor,
                                      canSubmit: canSubmit,
                                      isLoading: isLoading,
                                      onTurnstileToken: (token) {
                                        if (_turnstileToken == token) return;
                                        setState(() => _turnstileToken = token);
                                      },
                                      onTurnstileClear: () {
                                        if (_turnstileToken == null) return;
                                        setState(() => _turnstileToken = null);
                                      },
                                      onSubmit: _submit,
                                    );
                                  },
                                ),
                                _PasswordResetAcknowledgedBody(
                                  email: _emailController.text.trim(),
                                  compact: compact,
                                ),
                              ],
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

class _ForgotPasswordForm extends StatelessWidget {
  const _ForgotPasswordForm({
    required this.formKey,
    required this.compact,
    required this.submitted,
    required this.emailController,
    required this.turnstileKey,
    required this.fieldLabelColor,
    required this.canSubmit,
    required this.isLoading,
    required this.onTurnstileToken,
    required this.onTurnstileClear,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final bool compact;
  final bool submitted;
  final TextEditingController emailController;
  final GlobalKey<TurnstileChallengeState> turnstileKey;
  final Color fieldLabelColor;
  final bool canSubmit;
  final bool isLoading;
  final ValueChanged<String> onTurnstileToken;
  final VoidCallback onTurnstileClear;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Center(child: AuthBrandLogo(size: compact ? 64 : 72)),
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
            'Enter the email you use for ThriftLine. '
            'If that account has a password, we can email '
            'you a secure link to choose a new one.',
            style: AppTypography.body.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: compact ? 20 : 28),
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
          RepaintBoundary(
            child: TurnstileChallenge(
              key: turnstileKey,
              action: 'password_reset',
              showSuccessMessage: false,
              showLoadingMessage: false,
              onToken: onTurnstileToken,
              onError: (_) => onTurnstileClear(),
              onExpired: onTurnstileClear,
            ),
          ),
          SizedBox(height: compact ? 20 : 24),
          ThriftButton(
            label: 'Send reset link',
            onPressed: canSubmit ? onSubmit : null,
            isLoading: isLoading,
          ),
          SizedBox(height: compact ? 16 : 20),
          GestureDetector(
            onTap: () => context.go(RouteNames.emailLogin),
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
    );
  }
}

class _PasswordResetAcknowledgedBody extends StatelessWidget {
  const _PasswordResetAcknowledgedBody({
    required this.email,
    required this.compact,
  });

  final String email;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Center(child: AuthBrandLogo(size: compact ? 64 : 72)),
        SizedBox(height: compact ? 20 : 28),
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
          passwordResetAcknowledgementTitle,
          style: AppTypography.heading.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          passwordResetAcknowledgementBody(email),
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
