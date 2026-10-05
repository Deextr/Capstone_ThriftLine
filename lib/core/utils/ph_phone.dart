String? normalizePhMobile(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  }
  if (RegExp(r'^63[0-9]{10}$').hasMatch(digits)) {
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

/// Edit Profile / OTP: digits-only `09XXXXXXXXX` with explicit empty/length errors.
/// True when the form field mobile differs from the account's stored number.
bool phoneFieldDiffersFromAccount(String? accountPhone, String fieldRaw) {
  final field = normalizePhMobile(fieldRaw);
  if (field == null || !isPhMobile09Format(field)) return false;
  final stored = normalizePhMobile(accountPhone);
  return stored != field;
}

String? phMobile09EditProfileValidationError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Enter your phone number.';
  }
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 11) {
    return 'Phone number must contain exactly 11 digits.';
  }
  if (!RegExp(r'^09[0-9]{9}$').hasMatch(digits)) {
    return 'Enter a valid 11-digit Philippine mobile number starting with 09.';
  }
  return null;
}
