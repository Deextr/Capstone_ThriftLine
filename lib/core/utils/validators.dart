/// Form field validators for authentication screens.
abstract final class Validators {
  static const fullNameRequiredMessage = 'Please enter your full name.';

  static const fullNameInvalidMessage =
      'Full name can only include letters, spaces, hyphens, and apostrophes.';

  static const riderNameRequiredMessage = 'Enter the rider name.';

  static const riderNameInvalidMessage =
      'Rider name can only include letters, spaces, hyphens, and apostrophes.';

  /// Letters (any language), spaces, hyphens, and apostrophes between name parts.
  static final RegExp _fullNamePattern = RegExp(
    r"^(?:\p{L}+(?:['\u2019\-]\p{L}+)*)(?:\s+(?:\p{L}+(?:['\u2019\-]\p{L}+)*))*$",
    unicode: true,
  );

  /// Characters allowed while typing a full name.
  static final RegExp fullNameInputCharacters = RegExp(
    r"[\p{L}\s'\u2019\-]",
    unicode: true,
  );

  /// Trims edges and collapses repeated spaces between name parts.
  static String normalizeFullName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? username(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Username is required';
    if (trimmed.length < 3) return 'Username must be at least 3 characters';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  static String? name(String? value) {
    final raw = value ?? '';
    if (raw.trim().isEmpty) return fullNameRequiredMessage;

    final normalized = normalizeFullName(raw);
    if (!_fullNamePattern.hasMatch(normalized)) {
      return fullNameInvalidMessage;
    }
    return null;
  }

  static String? riderName(String? value) {
    final raw = value ?? '';
    if (raw.trim().isEmpty) return riderNameRequiredMessage;

    final normalized = normalizeFullName(raw);
    if (!_fullNamePattern.hasMatch(normalized)) {
      return riderNameInvalidMessage;
    }
    return null;
  }

  static String? password(String? value) {
    final trimmed = value ?? '';
    if (trimmed.isEmpty) return 'Please enter a password.';
    if (trimmed.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  static const int adminPasswordMinLength = 12;

  static const Set<String> _commonPasswords = {
    'password',
    'password123',
    'password1234',
    '123456789012',
    'qwertyuiopas',
    'admin1234567',
    'letmein12345',
    'welcome12345',
    'changeme1234',
    'thriftline123',
  };

  /// Stronger check used by Administrator / Superadmin password changes.
  static String? adminPassword(String? value) {
    final trimmed = value ?? '';
    if (trimmed.isEmpty) return 'Enter a new password.';
    if (trimmed.length < adminPasswordMinLength) {
      return 'Use at least $adminPasswordMinLength characters.';
    }
    if (_commonPasswords.contains(trimmed.toLowerCase())) {
      return 'Choose a less common password.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final confirm = value ?? '';
    if (confirm.isEmpty) return 'Please confirm your password.';
    if (confirm != password) return 'Passwords do not match.';
    return null;
  }

  static const int fullNameMaxLength = 80;

  static String? adminFullName(String? value) {
    final nameError = name(value);
    if (nameError != null) return nameError;
    if (normalizeFullName(value ?? '').length > fullNameMaxLength) {
      return 'Keep your name under $fullNameMaxLength characters.';
    }
    return null;
  }
}
