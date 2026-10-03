import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';

class EditProfileEmailSection extends StatefulWidget {
  const EditProfileEmailSection({
    super.key,
    required this.currentEmail,
    required this.canChangeEmail,
  });

  final String currentEmail;
  final bool canChangeEmail;

  @override
  State<EditProfileEmailSection> createState() =>
      _EditProfileEmailSectionState();
}

class _EditProfileEmailSectionState extends State<EditProfileEmailSection> {
  final _newEmailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _expanded = false;
  bool _codeSent = false;
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _newEmailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _newEmailCtrl.text.trim();
    if (!email.contains('@')) {
      showThriftSnackBar(context, 'Enter a valid email address.', isError: true);
      return;
    }
    setState(() => _sending = true);
    final error = await context.read<AuthProvider>().sendEmailChangeOtp(email);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _codeSent = error == null;
    });
    showThriftSnackBar(
      context,
      error ?? 'We sent a 6-digit code to $email.',
      isError: error != null,
    );
  }

  Future<void> _verify() async {
    final token = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (token.length < 6) {
      showThriftSnackBar(
        context,
        'Enter the 6-digit code from your email.',
        isError: true,
      );
      return;
    }
    setState(() => _verifying = true);
    final result = await context.read<AuthProvider>().confirmEmailChangeOtp(token);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (result.error != null) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    await context.read<AuthProvider>().reloadUser();
    if (!mounted) return;
    showThriftSnackBar(context, 'Email updated successfully.');
    setState(() {
      _expanded = false;
      _codeSent = false;
      _newEmailCtrl.clear();
      _otpCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Text(
                widget.currentEmail,
                style: AppTypography.body,
              ),
            ),
          ],
        ),
        if (widget.canChangeEmail) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Cancel email change' : 'Change email with OTP',
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'Email is managed by your sign-in provider.',
            style: AppTypography.caption.copyWith(color: AppColors.textHint),
          ),
        ],
        if (_expanded && widget.canChangeEmail) ...[
          const SizedBox(height: 8),
          ThriftTextField(
            label: 'New email',
            hint: 'you@example.com',
            controller: _newEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            icon: Icons.mark_email_unread_outlined,
          ),
          const SizedBox(height: 12),
          ThriftButton(
            label: _sending ? 'Sending…' : 'Send verification code',
            isLoading: _sending,
            onPressed: _sending ? null : _sendCode,
          ),
          if (_codeSent) ...[
            const SizedBox(height: 16),
            ThriftTextField(
              label: 'Verification code',
              hint: '6-digit code',
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              icon: Icons.pin_outlined,
            ),
            const SizedBox(height: 12),
            ThriftButton(
              label: _verifying ? 'Verifying…' : 'Confirm new email',
              isLoading: _verifying,
              onPressed: _verifying ? null : _verify,
            ),
          ],
        ],
      ],
    );
  }
}
