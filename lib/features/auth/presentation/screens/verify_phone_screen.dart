import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/phone_verification_controller.dart';
import '../../domain/phone_otp.dart';
import '../widgets/phone_otp_code_input.dart';

class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _codeCtrl;

  @override
  void initState() {
    super.initState();
    final controller = context.read<PhoneVerificationController>();
    _phoneCtrl = TextEditingController(text: controller.phone);
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ok = await context.read<PhoneVerificationController>().sendCode();
    if (!mounted || !ok) return;
    _codeCtrl.clear();
  }

  Future<void> _verify() async {
    final ok = await context.read<PhoneVerificationController>().verifyCode();
    if (!mounted || !ok) return;
    showThriftSnackBar(context, 'Phone number verified.');
    context.pop();
  }

  void _changeNumber() {
    context.read<PhoneVerificationController>().changePhoneNumber();
    _codeCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PhoneVerificationController>();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Phone number'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: controller.isBusy ? null : () => context.pop(),
          ),
        ),
        body: KeyboardSafeForm(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMd,
            AppConstants.spacingSm,
            AppConstants.spacingMd,
            AppConstants.spacingSm,
          ),
          action: controller.codeSent
              ? ThriftButton(
                  label: 'Verify',
                  isLoading: controller.isVerifying,
                  onPressed: controller.isBusy ? null : _verify,
                )
              : ThriftButton(
                  label: 'Send verification code',
                  isLoading: controller.isSending,
                  onPressed: controller.isBusy ? null : _send,
                ),
          children: [
            if (controller.isAlreadyVerified)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(
                  'This account already has a verified Philippine number.',
                  style: AppTypography.body.copyWith(color: AppColors.success),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.smartphone_outlined,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text('Verify Your Phone Number', style: AppTypography.heading),
            const SizedBox(height: 6),
            Text(
              controller.codeSent
                  ? 'We sent a verification code to ${controller.maskedPhone}'
                  : 'Enter your Philippine mobile number. We will send a 6-digit code by SMS.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            if (!controller.codeSent) ...[
              ThriftTextField(
                label: 'Mobile number',
                hint: '09XXXXXXXXX',
                controller: _phoneCtrl,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                error: controller.phoneError,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                onChanged: controller.updatePhone,
              ),
              if (controller.isDitoUnavailable) ...[
                const SizedBox(height: AppConstants.spacingMd),
                const _DitoUnavailableNotice(),
              ] else if (controller.errorMessage != null) ...[
                const SizedBox(height: AppConstants.spacingSm),
                Text(
                  controller.errorMessage!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ],
            ] else ...[
              PhoneOtpCodeInput(
                controller: _codeCtrl,
                enabled: !controller.isBusy,
                hasError:
                    controller.errorMessage != null &&
                    !controller.isDitoUnavailable,
                onChanged: controller.updateCode,
                onCompleted: (_) {
                  if (!controller.isBusy) _verify();
                },
              ),
              if (controller.isDitoUnavailable) ...[
                const SizedBox(height: AppConstants.spacingMd),
                const _DitoUnavailableNotice(),
              ] else if (controller.errorMessage != null) ...[
                const SizedBox(height: AppConstants.spacingSm),
                Text(
                  controller.errorMessage!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppConstants.spacingLg),
              Center(
                child: controller.canResend
                    ? TextButton(
                        onPressed: controller.isBusy ? null : _send,
                        child: Text(
                          'Resend OTP',
                          style: AppTypography.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Text(
                        'Resend code in ${controller.resendSeconds}s',
                        style: AppTypography.caption,
                      ),
              ),
              Center(
                child: TextButton(
                  onPressed: controller.isBusy ? null : _changeNumber,
                  child: Text(
                    'Change Phone Number',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DitoUnavailableNotice extends StatelessWidget {
  const _DitoUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Text(
        kDitoUnavailableMessage,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
    );
  }
}
