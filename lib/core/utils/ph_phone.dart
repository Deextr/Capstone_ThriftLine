String? normalizePhMobile(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  }
  // Philippine mobiles are +639XXXXXXXXX. Do not treat other +63 numbers as mobiles.
  if (RegExp(r'^639[0-9]{9}$').hasMatch(digits)) {
    return '0${digits.substring(2)}';
  }
  if (RegExp(r'^9[0-9]{9}$').hasMatch(digits)) {
    return '0$digits';
  }
  if (RegExp(r'^09[0-9]{9}$').hasMatch(digits)) {
    return digits;
  }
  return null;
}

bool isValidPhMobile(String? raw) => normalizePhMobile(raw) != null;

/// Formats a valid Philippine mobile number for human-readable display without
/// changing the number stored in the database.
String formatPhMobile(String? raw) {
  final normalized = normalizePhMobile(raw);
  if (normalized == null) return raw?.trim() ?? '';
  return '${normalized.substring(0, 4)} '
      '${normalized.substring(4, 7)} '
      '${normalized.substring(7)}';
}

String? phMobileValidationError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Please enter a valid phone number.';
  }
  if (normalizePhMobile(raw) == null) {
    return 'Please enter a valid phone number.';
  }
  return null;
}

/// Buyer delivery contact: exactly 11 digits starting with `09`, digits only.
bool isPhMobile09Format(String? raw) {
  if (raw == null) return false;
  return RegExp(r'^09[0-9]{9}$').hasMatch(raw.trim());
}

String? phMobile09FormatValidationError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Enter a Philippine mobile number.';
  }
  if (!isPhMobile09Format(raw)) {
    return 'Enter a valid 11-digit mobile number starting with 09.';
  }
  return null;
}

/// Field text for the OTP phone input.
///
/// A complete international number (`+639…`, `639…`, or `9XXXXXXXXX`) collapses
/// to `09XXXXXXXXX` before the 11-digit rule runs. Truncating `+639…` to 11
/// digits first produces `639…` and a false "must start with 09" error.
/// Once a valid local number is present, extra digits are ignored.
String collapsePhMobileFieldText(String raw, {String? previous}) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final normalized = normalizePhMobile(digits);
  if (normalized != null) return normalized;
  final previousNormalized = normalizePhMobile(previous);
  if (previousNormalized != null && digits.length > previousNormalized.length) {
    return previousNormalized;
  }
  if (digits.length > 12) return digits.substring(0, 12);
  return digits;
}

/// True when the form field mobile differs from the account's stored number.
bool phoneFieldDiffersFromAccount(String? accountPhone, String fieldRaw) {
  final field = normalizePhMobile(fieldRaw);
  if (field == null || !isPhMobile09Format(field)) return false;
  final stored = normalizePhMobile(accountPhone);
  return stored != field;
}

/// Edit Profile / OTP: `09XXXXXXXXX`, including `+63` input before it is collapsed.
String? phMobile09EditProfileValidationError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Enter your phone number.';
  }
  if (normalizePhMobile(raw) != null) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return 'Enter a valid 11-digit Philippine mobile number starting with 09.';
  }
  if (_localMobileDigitLength(digits) != 11) {
    return 'Phone number must contain exactly 11 digits.';
  }
  return 'Enter a valid 11-digit Philippine mobile number starting with 09.';
}

/// Length of [digits] expressed as a local `09…` number, without accepting it.
int _localMobileDigitLength(String digits) {
  if (digits.startsWith('63')) return digits.length - 1;
  if (digits.startsWith('9')) return digits.length + 1;
  return digits.length;
}
