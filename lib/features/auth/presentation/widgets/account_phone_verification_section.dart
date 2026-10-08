import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/phone_verification_controller.dart';
import '../../domain/phone_otp.dart';
import 'phone_otp_code_input.dart';

/// Account-level phone on `users.phone_number` with SMS OTP (Edge Functions).
///
/// Shared by Edit Profile and Become a Seller so validation and OTP UX stay identical.
class AccountPhoneVerificationSection extends StatefulWidget {
  const AccountPhoneVerificationSection({
    super.key,
    required this.phoneController,
    this.onVerified,
    this.sectionTitle = 'Phone number',
    this.intro,
    this.sendOtpButtonLabel = 'Verify',
  });

  final TextEditingController phoneController;
  final VoidCallback? onVerified;
  final String sectionTitle;
  final String? intro;
  final String sendOtpButtonLabel;

  @override
  State<AccountPhoneVerificationSection> createState() =>
      _AccountPhoneVerificationSectionState();
}

class _AccountPhoneVerificationSectionState
    extends State<AccountPhoneVerificationSection> {
  late final PhoneVerificationController _otp;
  late final FocusNode _phoneFocus;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _phoneFocus = FocusNode();
    _otp = PhoneVerificationController(
      auth: auth,
      initialPhone: widget.phoneController.text,
    );
    widget.phoneController.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.phoneController.removeListener(_syncFromController);
    _phoneFocus.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _startChangeNumber() {
    _phoneFocus.requestFocus();
    final text = widget.phoneController.text;
    widget.phoneController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
    showThriftSnackBar(
      context,
      'Enter your new number, then tap ${widget.sendOtpButtonLabel}.',
    );
  }

  void _syncFromController() {
    _otp.syncPhoneFromField(widget.phoneController.text);
  }

  void _onVerified() {
    final verified = normalizePhMobile(
      context.read<AuthProvider>().user?.phone,
    );
    if (verified != null) {
      widget.phoneController.text = verified;
    }
    widget.onVerified?.call();
    setState(() {});
  }

  Future<void> _startVerify() async {
    FocusScope.of(context).unfocus();
    _otp.syncPhoneFromField(widget.phoneController.text);
    final ok = await _otp.sendCode(editProfileCopy: true);
    if (!mounted) return;
    if (!ok) {
      if (_otp.phoneError != null) {
        setState(() {});
      }
      return;
    }
    if (_otp.isVerifiedForEnteredPhone) {
      showThriftSnackBar(
        context,
        'This is already your verified phone number.',
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: _otp,
        child: PhoneOtpEntrySheet(
          onVerified: () {
            _onVerified();
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    return ListenableBuilder(
      listenable: _otp,
      builder: (context, _) {
        final verified = _otp.isVerifiedForEnteredPhone;
        final changingVerified = _otp.isChangingVerifiedPhone;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.intro != null) ...[
              Text(
                widget.intro!,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.sectionTitle,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (verified)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Not verified',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
            if (verified) ...[
              const SizedBox(height: 4),
              Text(
                'Tap Change to replace your verified number, or edit the field '
                'and tap ${widget.sendOtpButtonLabel}.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                  height: 1.35,
                ),
              ),
            ] else if (changingVerified) ...[
              const SizedBox(height: 4),
              Text(
                'Your previous verified number stays active until you verify '
                'this new number.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacingXs),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextFormField(
                      focusNode: _phoneFocus,
                      controller: widget.phoneController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: false,
                        decimal: false,
                      ),
                      inputFormatters: const [_PhMobileFieldFormatter()],
                      onChanged: (value) {
                        _otp.syncPhoneFromField(value);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: '09XXXXXXXXX',
                        prefixIcon: const Icon(
                          Icons.phone_outlined,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _otp.phoneError != null
                                ? AppColors.error
                                : AppColors.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PhoneVerifyTrailing(
                    verified: verified,
                    isBusy: _otp.isBusy,
                    isSending: _otp.isSending,
                    onVerify: _startVerify,
                    onChangeNumber: _startChangeNumber,
                    actionLabel: widget.sendOtpButtonLabel,
                  ),
                ],
              ),
            ),
            if (_otp.phoneError != null) ...[
              const SizedBox(height: 6),
              Text(
                _otp.phoneError!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ] else if (_otp.errorMessage != null &&
                !_otp.isSmsNetworkUnavailable) ...[
              const SizedBox(height: 6),
              Text(
                _otp.errorMessage!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ],
            if (_otp.isSmsNetworkUnavailable) ...[
              const SizedBox(height: 8),
              Text(
                kSmsNetworkUnavailableMessage,
                style: AppTypography.caption.copyWith(
                  color: AppColors.error,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart & TNT temporarily unavailable',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Please use Globe, TM, or DITO for SMS verification.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhoneVerifyTrailing extends StatelessWidget {
  const _PhoneVerifyTrailing({
    required this.verified,
    required this.isBusy,
    required this.isSending,
    required this.onVerify,
    required this.onChangeNumber,
    this.actionLabel = 'Verify',
  });

  final bool verified;
  final bool isBusy;
  final bool isSending;
  final VoidCallback onVerify;
  final VoidCallback onChangeNumber;
  final String actionLabel;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    if (verified) {
      return TextButton(
        onPressed: isBusy ? null : onChangeNumber,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: _radius,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          'Change',
          style: AppTypography.body.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return TextButton(
      onPressed: isBusy ? null : onVerify,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: _radius,
          side: const BorderSide(color: AppColors.primary),
        ),
      ),
      child: isSending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : Text(
              actionLabel,
              style: AppTypography.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Collapses `+639…` / `639…` to `09XXXXXXXXX` before the 11-digit check.
class _PhMobileFieldFormatter extends TextInputFormatter {
  const _PhMobileFieldFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = collapsePhMobileFieldText(
      newValue.text,
      previous: oldValue.text,
    );
    if (text == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// OTP entry sheet after [PhoneVerificationController.sendCode] succeeds.
class PhoneOtpEntrySheet extends StatefulWidget {
  const PhoneOtpEntrySheet({super.key, required this.onVerified});

  final VoidCallback onVerified;

  @override
  State<PhoneOtpEntrySheet> createState() => _PhoneOtpEntrySheetState();
}

class _PhoneOtpEntrySheetState extends State<PhoneOtpEntrySheet> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final ok = await context.read<PhoneVerificationController>().verifyCode();
    if (!mounted || !ok) return;
    widget.onVerified();
  }

  Future<void> _resend() async {
    final ok = await context.read<PhoneVerificationController>().sendCode(
      editProfileCopy: true,
    );
    if (!mounted || !ok) return;
    _codeCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PhoneVerificationController>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Enter verification code', style: AppTypography.subheading),
          const SizedBox(height: 6),
          Text(
            'We sent a 6-digit code to ${controller.maskedPhone}',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          PhoneOtpCodeInput(
            controller: _codeCtrl,
            enabled: !controller.isBusy,
            hasError:
                controller.errorMessage != null &&
                !controller.isSmsNetworkUnavailable,
            onChanged: controller.updateCode,
            onCompleted: (_) {
              if (!controller.isBusy) _verify();
            },
          ),
          if (controller.isSmsNetworkUnavailable) ...[
            const SizedBox(height: 12),
            Text(
              kSmsNetworkUnavailableMessage,
              style: AppTypography.caption.copyWith(
                color: AppColors.error,
                height: 1.35,
              ),
            ),
          ] else if (controller.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.errorMessage!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: controller.isVerifying ? null : _verify,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: controller.isVerifying
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verify'),
          ),
          const SizedBox(height: 8),
          Center(
            child: controller.canResend
                ? TextButton(
                    onPressed: controller.isBusy ? null : _resend,
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
        ],
      ),
    );
  }
}
