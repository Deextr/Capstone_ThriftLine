import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/ph_phone.dart';
import '../../../providers/auth_provider.dart';
import '../domain/phone_otp.dart';
import '../domain/trusted_device.dart';

class PhoneVerificationController extends ChangeNotifier {
  PhoneVerificationController({
    required AuthProvider auth,
    String? initialPhone,
  }) : _auth = auth {
    final existing = normalizePhMobile(initialPhone) ?? '';
    phone = isPhMobile09Format(existing) ? existing : '';
  }

  final AuthProvider _auth;

  String phone = '';
  String code = '';
  String? phoneError;
  String? errorMessage;
  bool codeSent = false;
  bool isSending = false;
  bool isVerifying = false;
  int resendSeconds = 0;
  Timer? _resendTimer;

  bool get isBusy => isSending || isVerifying;
  bool get canResend => codeSent && resendSeconds <= 0 && !isBusy;
  bool get isSmsNetworkUnavailable =>
      errorMessage != null &&
      (errorMessage == kSmsNetworkUnavailableMessage ||
          errorMessage!.contains(
            'SMS verification is currently unavailable for this mobile number',
          ));

  /// @deprecated Use [isSmsNetworkUnavailable].
  bool get isDitoUnavailable => isSmsNetworkUnavailable;
  bool get isAlreadyVerified => isVerifiedForEnteredPhone;

  /// Verified only when auth says so **and** it matches the number in the field.
  bool get accountHasVerifiedPhone =>
      _auth.user?.hasVerifiedAccountPhone ?? false;

  /// User is replacing an already verified account mobile with a new one.
  bool get isChangingVerifiedPhone =>
      accountHasVerifiedPhone && !isVerifiedForEnteredPhone;

  bool get isVerifiedForEnteredPhone {
    final user = _auth.user;
    if (user == null || !user.isPhoneVerified) return false;
    final stored = normalizePhMobile(user.phone);
    final entered = normalizePhMobile(phone);
    return stored != null &&
        entered != null &&
        stored == entered &&
        isPhMobile09Format(entered);
  }

  String get maskedPhone => maskPhMobileForOtp(phone);

  void syncPhoneFromField(String raw) {
    final normalized = normalizePhMobile(raw);
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    phone = normalized ?? digits;
    phoneError = null;
    if (codeSent && !isVerifiedForEnteredPhone) {
      changePhoneNumber();
    }
    if (isSmsNetworkUnavailable) errorMessage = null;
    notifyListeners();
  }

  void updatePhone(String value) {
    phone = value.replaceAll(RegExp(r'\D'), '');
    phoneError = null;
    if (isSmsNetworkUnavailable) errorMessage = null;
    notifyListeners();
  }

  void updateCode(String value) {
    code = value.replaceAll(RegExp(r'\D'), '');
    if (errorMessage != null && !isSmsNetworkUnavailable) {
      errorMessage = null;
    }
    notifyListeners();
  }

  void changePhoneNumber() {
    codeSent = false;
    code = '';
    errorMessage = null;
    resendSeconds = 0;
    _resendTimer?.cancel();
    notifyListeners();
  }

  Future<bool> sendCode({bool editProfileCopy = false}) async {
    final canonical = normalizePhMobile(phone);
    if (canonical != null) phone = canonical;
    phoneError = editProfileCopy
        ? phMobile09EditProfileValidationError(phone)
        : phMobile09FormatValidationError(phone);
    if (phoneError != null) {
      notifyListeners();
      return false;
    }

    if (isVerifiedForEnteredPhone) {
      return true;
    }

    isSending = true;
    errorMessage = null;
    notifyListeners();

    final result = await _auth.sendPhoneOtp(phone);
    if (!hasListeners) return false;

    isSending = false;
    if (!result.isOk) {
      errorMessage = phoneOtpUserMessage(
        result,
        fallback: 'We couldn\'t send the verification code. Please try again.',
      );
      if (result.code == PhoneOtpErrorCode.invalidPhone ||
          result.code == PhoneOtpErrorCode.phoneAlreadyInUse) {
        phoneError = errorMessage;
        errorMessage = null;
      }
      if (result.retryAfterSeconds != null && result.retryAfterSeconds! > 0) {
        _startResendCountdown(result.retryAfterSeconds!);
      }
      notifyListeners();
      return false;
    }

    codeSent = true;
    errorMessage = null;
    _startResendCountdown(result.retryAfterSeconds ?? 60);
    notifyListeners();
    return true;
  }

  Future<bool> verifyCode() async {
    if (code.length < 6) {
      errorMessage = 'Enter the 6-digit code from the SMS.';
      notifyListeners();
      return false;
    }

    isVerifying = true;
    errorMessage = null;
    notifyListeners();

    final deviceToken = await _auth.deviceInstallTokenForRisk();
    final result = await _auth.verifyPhoneOtp(
      phone: phone,
      token: code,
      deviceToken: deviceToken,
      platform: trustedDevicePlatformLabel(defaultTargetPlatform),
    );
    if (!hasListeners) return false;

    isVerifying = false;
    if (!result.isOk) {
      errorMessage = phoneOtpUserMessage(
        result,
        fallback: 'The verification code is incorrect.',
      );
      if (result.code == PhoneOtpErrorCode.phoneAlreadyInUse) {
        phoneError = errorMessage;
        errorMessage = null;
        codeSent = false;
      }
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    resendSeconds = seconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendSeconds <= 1) {
        resendSeconds = 0;
        timer.cancel();
      } else {
        resendSeconds -= 1;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}
