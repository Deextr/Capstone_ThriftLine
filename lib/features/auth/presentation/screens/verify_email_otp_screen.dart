import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../widgets/auth_branding.dart';
import '../widgets/login_video_background.dart';

class VerifyEmailOtpScreen extends StatefulWidget {
  const VerifyEmailOtpScreen({super.key});

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    context.go(RouteNames.login);
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    final error = await context.read<AuthProvider>().sendEmailOtp();
    if (!mounted) return;
    setState(() => _sending = false);
    showThriftSnackBar(
      context,
      error ?? 'We sent a new 6-digit code to your email.',
      isError: error != null,
    );
  }

  Future<void> _verify() async {
    final token = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (token.length < 6) {
      showThriftSnackBar(
        context,
        'Enter the 6-digit code from your email.',
        isError: true,
      );
      return;
    }

    setState(() => _verifying = true);
    final auth = context.read<AuthProvider>();
    final error = await auth.verifyEmailOtp(token: token);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    context.go(auth.homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = auth.user?.email ?? 'your email';
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
                      onPressed: auth.isLoading || _verifying ? null : _cancel,
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
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Center(
                                  child: AuthBrandLogo(
                                    size: compact ? 84 : 100,
                                  ),
                                ),
                                SizedBox(height: compact ? 16 : 24),
                                Text(
                                  'Check your email',
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
                                  'We sent a 6-digit code to $email. '
                                  'Enter it to finish signing in.',
                                  style: AppTypography.body.copyWith(
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: compact ? 28 : 40),
                                ThriftTextField(
                                  label: '6-digit code',
                                  hint: '123456',
                                  controller: _codeCtrl,
                                  icon: Icons.lock_outline,
                                  keyboardType: TextInputType.number,
                                  labelColor: fieldLabelColor,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                ),
                                SizedBox(height: compact ? 20 : 24),
                                ThriftButton(
                                  label: 'Verify code',
                                  onPressed: _verifying || _sending
                                      ? null
                                      : _verify,
                                  isLoading: _verifying,
                                ),
                                const SizedBox(height: 16),
                                ThriftButton(
                                  label: 'Resend code',
                                  variant: ThriftButtonVariant.outline,
                                  color: Colors.white,
                                  onPressed: _verifying || _sending
                                      ? null
                                      : _resend,
                                  isLoading: _sending,
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
