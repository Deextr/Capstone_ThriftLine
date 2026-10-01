import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/password_recovery_coordinator.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../widgets/auth_branding.dart';
import '../widgets/login_video_background.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _resetComplete = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _canResetPassword(AuthProvider auth, PasswordRecoveryCoordinator links) {
    return auth.isPasswordRecoveryActive &&
        auth.isAuthenticated &&
        links.linkError == null;
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final links = context.read<PasswordRecoveryCoordinator>();
    if (!_canResetPassword(auth, links)) return;

    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final error = await auth.completePasswordReset(
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    links.clearLinkError();
    setState(() => _resetComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final links = context.watch<PasswordRecoveryCoordinator>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 700;
    const fieldLabelColor = Colors.white;

    final linkError = links.linkError;
    final canReset = _canResetPassword(auth, links);

    if (_resetComplete) {
      return _ResetSuccessScaffold(compact: compact);
    }

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
                              minHeight:
                                  constraints.maxHeight -
                                  (compact ? 4 : AppConstants.spacingSm) -
                                  AppConstants.spacingLg,
                            ),
                            child: linkError != null || !canReset
                                ? _InvalidLinkBody(
                                    message:
                                        linkError ??
                                        'Open the password reset link from your '
                                            'email on this device to continue.',
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
                                          'Choose a new password',
                                          style: AppTypography.heading.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Create a strong password you have not used '
                                          'on ThriftLine before.',
                                          style: AppTypography.body.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: compact ? 24 : 32),
                                        ThriftTextField(
                                          label: 'New password',
                                          controller: _passwordController,
                                          obscureText: _obscurePassword,
                                          icon: Icons.lock_outline,
                                          validator: Validators.password,
                                          labelColor: fieldLabelColor,
                                          suffix: IconButton(
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ThriftTextField(
                                          label: 'Confirm password',
                                          controller:
                                              _confirmPasswordController,
                                          obscureText: _obscurePassword,
                                          icon: Icons.lock_reset_outlined,
                                          validator: (value) =>
                                              Validators.confirmPassword(
                                                value,
                                                _passwordController.text,
                                              ),
                                          labelColor: fieldLabelColor,
                                        ),
                                        SizedBox(height: compact ? 20 : 24),
                                        ThriftButton(
                                          label: 'Update password',
                                          onPressed: auth.isLoading
                                              ? null
                                              : _submit,
                                          isLoading: auth.isLoading,
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

class _InvalidLinkBody extends StatelessWidget {
  const _InvalidLinkBody({required this.message, required this.compact});

  final String message;
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
              color: AppColors.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
            ),
            child: const Icon(
              Icons.link_off_outlined,
              color: AppColors.error,
              size: 34,
            ),
          ),
        ),
        SizedBox(height: compact ? 20 : 28),
        Text(
          'Reset link problem',
          style: AppTypography.heading.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: AppTypography.body.copyWith(
            color: Colors.white.withValues(alpha: 0.82),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: compact ? 28 : 36),
        ThriftButton(
          label: 'Request new link',
          onPressed: () => context.go(RouteNames.forgotPassword),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go(RouteNames.login),
          child: Text(
            'Back to login',
            style: AppTypography.body.copyWith(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResetSuccessScaffold extends StatelessWidget {
  const _ResetSuccessScaffold({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LoginVideoBackground(),
          const AuthVideoScrim(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 20 : 28),
                  Text(
                    'Password updated',
                    style: AppTypography.heading.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your password was changed successfully. Sign in with your '
                    'new password to continue.',
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
