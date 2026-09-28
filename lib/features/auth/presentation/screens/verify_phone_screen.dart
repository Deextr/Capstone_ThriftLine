import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  late final TextEditingController _phoneCtrl;
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AuthProvider>().user?.phone ?? '';
    _phoneCtrl = TextEditingController(text: existing);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final error = await context.read<AuthProvider>().sendPhoneOtp(_phoneCtrl.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _codeSent = error == null;
    });
    showThriftSnackBar(
      context,
      error ?? 'We sent a 6-digit code to that number.',
      isError: error != null,
    );
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final error = await context.read<AuthProvider>().verifyPhoneOtp(
          phone: _phoneCtrl.text,
          token: _codeCtrl.text,
        );
    if (!mounted) return;
    setState(() => _verifying = false);
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Phone number verified.');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final verified = context.watch<AuthProvider>().user?.isPhoneVerified ?? false;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verify phone'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (verified)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'This account already has a verified Philippine number.',
                    style: AppTypography.body.copyWith(color: AppColors.success),
                  ),
                ),
              Text(
                'OTP is sent by FMCSMS from our server. The app never stores the SMS API key or the code hash.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 16),
              ThriftTextField(
                label: 'Mobile number',
                hint: '09XXXXXXXXX',
                controller: _phoneCtrl,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              ThriftButton(
                label: _codeSent ? 'Resend code' : 'Send code',
                isLoading: _sending,
                onPressed: _sending ? null : _send,
              ),
              if (_codeSent) ...[
                const SizedBox(height: 24),
                ThriftTextField(
                  label: '6-digit code',
                  hint: '123456',
                  controller: _codeCtrl,
                  icon: Icons.lock_outline,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                ThriftButton(
                  label: 'Verify',
                  isLoading: _verifying,
                  onPressed: _verifying ? null : _verify,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
