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

class AdminVerifyEmailOtpScreen extends StatefulWidget {
  const AdminVerifyEmailOtpScreen({super.key});

  @override
  State<AdminVerifyEmailOtpScreen> createState() =>
      _AdminVerifyEmailOtpScreenState();
}

class _AdminVerifyEmailOtpScreenState extends State<AdminVerifyEmailOtpScreen> {
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
    context.go(RouteNames.adminLogin);
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
    context.go(RouteNames.adminDashboard);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = auth.user?.email ?? 'your email';
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppConstants.breakpointTablet;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: auth.isLoading || _verifying
                              ? null
                              : _cancel,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back to sign in'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check your email',
                        style: AppTypography.display.copyWith(
                          fontSize: compact ? 22 : 24,
                          letterSpacing: -0.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a 6-digit code to $email. '
                        'Enter it to finish signing in to the admin portal.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _codeCtrl,
                        enabled: !_verifying && !_sending,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '6-digit code',
                          hintText: '123456',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onSubmitted: (_) {
                          if (!_verifying && !_sending) _verify();
                        },
                      ),
                      const SizedBox(height: 24),
                      ThriftButton(
                        label: 'Verify code',
                        onPressed: _verifying || _sending ? null : _verify,
                        isLoading: _verifying,
                      ),
                      const SizedBox(height: 12),
                      ThriftButton(
                        label: 'Resend code',
                        variant: ThriftButtonVariant.outline,
                        onPressed: _verifying || _sending ? null : _resend,
                        isLoading: _sending,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
