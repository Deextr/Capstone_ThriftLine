/// Structured result from the phone OTP Edge Functions.
class PhoneOtpResult {
  const PhoneOtpResult._({this.error, this.code, this.retryAfterSeconds});

  const PhoneOtpResult.success({int? retryAfterSeconds})
    : this._(retryAfterSeconds: retryAfterSeconds);

  const PhoneOtpResult.failure(
    String error, {
    String? code,
    int? retryAfterSeconds,
  }) : this._(error: error, code: code, retryAfterSeconds: retryAfterSeconds);

  final String? error;
  final String? code;
  final int? retryAfterSeconds;

  bool get isOk => error == null;
  bool get isDitoUnavailable => code == PhoneOtpErrorCode.ditoUnavailable;
}

abstract final class PhoneOtpErrorCode {
  static const String ditoUnavailable = 'dito_unavailable';
  static const String resendCooldown = 'resend_cooldown';
  static const String rateLimited = 'rate_limited';
  static const String invalidPhone = 'invalid_phone';
  static const String invalidCode = 'invalid_code';
  static const String expired = 'expired';
  static const String alreadyUsed = 'already_used';
  static const String tooManyAttempts = 'too_many_attempts';
}

const String kDitoUnavailableMessage =
    'SMS verification for DITO numbers is currently unavailable due to provider maintenance. Please use a supported mobile network or try again later.';

/// Masks a verified or in-progress number after the SMS has been sent.
///
/// Example: `09171234567` → `09••• ••••567`
String maskPhMobileForOtp(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 3) return '09••• ••••';
  final local = digits.length == 12 && digits.startsWith('63')
      ? '0${digits.substring(2)}'
      : digits.length == 10 && digits.startsWith('9')
      ? '0$digits'
      : digits;
  if (local.length < 11) {
    return '09••• ••••${local.substring(local.length - 3)}';
  }
  return '${local.substring(0, 2)}••• ••••${local.substring(local.length - 3)}';
}
