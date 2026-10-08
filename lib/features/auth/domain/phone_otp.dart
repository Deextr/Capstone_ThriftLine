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

  bool get isSmsNetworkUnavailable =>
      code == PhoneOtpErrorCode.networkUnavailable ||
      code == PhoneOtpErrorCode.ditoUnavailable;

  /// @deprecated Use [isSmsNetworkUnavailable].
  bool get isDitoUnavailable => isSmsNetworkUnavailable;
}

abstract final class PhoneOtpErrorCode {
  static const String networkUnavailable = 'network_unavailable';

  /// Legacy FMCSMS code; backend may still emit during transition.
  static const String ditoUnavailable = 'dito_unavailable';
  static const String resendCooldown = 'resend_cooldown';
  static const String rateLimited = 'rate_limited';
  static const String invalidPhone = 'invalid_phone';
  static const String invalidCode = 'invalid_code';
  static const String expired = 'expired';
  static const String alreadyUsed = 'already_used';
  static const String tooManyAttempts = 'too_many_attempts';
  static const String phoneAlreadyInUse = 'phone_already_in_use';
  static const String providerAuth = 'provider_auth';
  static const String providerCredits = 'provider_credits';
  static const String providerError = 'provider_error';
  static const String providerTimeout = 'provider_timeout';
  static const String sendFailed = 'send_failed';
  static const String unavailable = 'unavailable';
}

const String kSmsDeliveryUnavailableMessage =
    'Unable to send a verification code right now. Please try again later.';

const String kPhoneAlreadyInUseMessage =
    'This phone number is already in use. Please use a different phone number.';

const String kSmsNetworkUnavailableMessage =
    'SMS verification is currently unavailable for this mobile number. Please use another supported number or try again later.';

/// Subtle notice on Edit Profile (provider limitation); not shown as a field error.
const String kSmartTntMaintenanceNotice =
    'SMS verification for Smart and TNT numbers is currently unavailable due to provider maintenance. Please use a supported mobile number or try again later.';

/// Maps Edge Function codes to Buyer-facing copy (no raw API/JSON).
String phoneOtpUserMessage(PhoneOtpResult result, {String? fallback}) {
  if (result.isOk) return '';
  switch (result.code) {
    case PhoneOtpErrorCode.invalidPhone:
      return 'Enter a valid 11-digit Philippine mobile number starting with 09.';
    case PhoneOtpErrorCode.invalidCode:
      return 'The verification code is incorrect.';
    case PhoneOtpErrorCode.expired:
      return 'This verification code has expired. Request a new code.';
    case PhoneOtpErrorCode.resendCooldown:
      final wait = result.error?.trim();
      if (wait != null && wait.isNotEmpty) return wait;
      return 'Too many verification attempts. Please wait before trying again.';
    case PhoneOtpErrorCode.tooManyAttempts:
    case PhoneOtpErrorCode.rateLimited:
      return 'Too many verification attempts. Please wait before trying again.';
    case PhoneOtpErrorCode.networkUnavailable:
    case PhoneOtpErrorCode.ditoUnavailable:
      return kSmsNetworkUnavailableMessage;
    case PhoneOtpErrorCode.phoneAlreadyInUse:
      return kPhoneAlreadyInUseMessage;
    case PhoneOtpErrorCode.providerAuth:
    case PhoneOtpErrorCode.providerCredits:
    case PhoneOtpErrorCode.providerError:
    case PhoneOtpErrorCode.providerTimeout:
    case PhoneOtpErrorCode.sendFailed:
    case PhoneOtpErrorCode.unavailable:
      return kSmsDeliveryUnavailableMessage;
    default:
      final text = result.error?.trim();
      if (text != null && text.isNotEmpty) {
        final lower = text.toLowerCase();
        if (lower.contains('{') ||
            lower.contains('unisms') ||
            lower.contains('secret') ||
            lower.contains('fail_reason') ||
            lower.contains('api key')) {
          return kSmsDeliveryUnavailableMessage;
        }
        if (lower.contains('connection') || lower.contains('network')) {
          return 'Check your internet connection and try again.';
        }
        if (lower.contains('send')) {
          return kSmsDeliveryUnavailableMessage;
        }
        return text;
      }
      return fallback ?? kSmsDeliveryUnavailableMessage;
  }
}

/// @deprecated Use [kSmsNetworkUnavailableMessage].
const String kDitoUnavailableMessage = kSmsNetworkUnavailableMessage;

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
