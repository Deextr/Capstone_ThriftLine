import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/ph_phone.dart';
import '../../../providers/auth_provider.dart';
import '../domain/phone_otp.dart';

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
  bool get isDitoUnavailable =>
      errorMessage != null &&
      (errorMessage == kDitoUnavailableMessage ||
          errorMessage!.contains('DITO numbers is currently unavailable'));
  bool get isAlreadyVerified => _auth.user?.isPhoneVerified == true;
  String get maskedPhone => maskPhMobileForOtp(phone);

  void updatePhone(String value) {
    phone = value.replaceAll(RegExp(r'\D'), '');
    phoneError = null;
    if (isDitoUnavailable) errorMessage = null;
    notifyListeners();
  }

  void updateCode(String value) {
    code = value.replaceAll(RegExp(r'\D'), '');
    if (errorMessage != null && !isDitoUnavailable) {
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

  Future<bool> sendCode() async {
    phoneError = phMobile09FormatValidationError(phone);
    if (phoneError != null) {
      notifyListeners();
      return false;
    }

    isSending = true;
    errorMessage = null;
    notifyListeners();

    final result = await _auth.sendPhoneOtp(phone);
    if (!hasListeners) return false;

    isSending = false;
    if (!result.isOk) {
      errorMessage = result.error;
      if (result.code == PhoneOtpErrorCode.invalidPhone) {
        phoneError = result.error;
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

    final result = await _auth.verifyPhoneOtp(phone: phone, token: code);
    if (!hasListeners) return false;

    isVerifying = false;
    if (!result.isOk) {
      errorMessage = result.error;
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
