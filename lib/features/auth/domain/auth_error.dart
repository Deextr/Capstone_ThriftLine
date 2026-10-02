import 'dart:convert';

/// Normalized GoTrue error. Some 500s put `code` and `message` inside a JSON
/// string, so [AuthException.code] is empty and the UI falls through to a
/// generic "Something went wrong".
class GoTrueErrorInfo {
  const GoTrueErrorInfo({this.code, required this.message});

  final String? code;
  final String message;
}

GoTrueErrorInfo parseGoTrueError({String? code, required String message}) {
  var resolvedCode = (code == null || code.isEmpty || code == '-')
      ? null
      : code;
  var resolvedMessage = message;
  final trimmed = message.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final nestedCode = decoded['code'];
        final nestedMessage = decoded['message'];
        if (nestedCode is String && nestedCode.isNotEmpty) {
          resolvedCode = nestedCode;
        }
        if (nestedMessage is String && nestedMessage.isNotEmpty) {
          resolvedMessage = nestedMessage;
        }
      }
    } catch (_) {}
  }
  return GoTrueErrorInfo(code: resolvedCode, message: resolvedMessage);
}

/// True when signup was refused because this account already has a
/// non-email provider. Matches the identity trigger and GoTrue's
/// "Error creating identity" response. A plain "user already registered"
/// error is not enough to claim the account is Google.
bool isOauthAccountSignupBlocked(GoTrueErrorInfo info) {
  final msg = info.message.toLowerCase();
  return msg.contains('creating identity') ||
      msg.contains('an account with this email already exists');
}

/// Safe copy for the password-reset Edge Function. Unknown server text is
/// collapsed so logs and gateway errors are not shown to the user.
String passwordResetUiMessage(String? serverError) {
  final msg = (serverError ?? '').toLowerCase();
  if (msg.contains('human verification') ||
      msg.contains('verification failed') ||
      msg.contains('verification expired')) {
    return serverError!.trim();
  }
  if (msg.contains('too many') || msg.contains('wait a moment')) {
    return 'Too many reset emails requested. Please wait a moment and '
        'try again.';
  }
  if (msg.contains('valid email')) {
    return 'Enter a valid email address.';
  }
  return 'We could not send the reset email right now. '
      'Please try again in a moment.';
}

/// Maps `sign-in-with-email` Edge Function codes to user-facing copy.
String emailLoginUiMessage({String? code, String? serverError}) {
  final normalizedCode = code?.toLowerCase().trim();
  switch (normalizedCode) {
    case 'invalid_credentials':
      return 'Invalid email or password. Please try again.';
    case 'turnstile_required':
      return 'Complete human verification before signing in.';
    case 'turnstile_failed':
      return serverError?.trim().isNotEmpty == true
          ? serverError!.trim()
          : 'Human verification failed. Please try again.';
    case 'rate_limited':
      return serverError?.trim().isNotEmpty == true
          ? serverError!.trim()
          : 'Too many attempts. Please wait a moment and try again.';
    case 'unavailable':
      return 'Sign-in is temporarily unavailable. Please try again.';
  }

  final msg = (serverError ?? '').toLowerCase();
  if (msg.contains('invalid email or password')) {
    return 'Invalid email or password. Please try again.';
  }
  if (msg.contains('verification')) {
    return serverError!.trim();
  }
  if (msg.contains('too many')) {
    return serverError!.trim();
  }
  return 'Something went wrong. Please try again.';
}

bool isExistingAccountAuthError(GoTrueErrorInfo info) {
  final code = info.code?.toLowerCase() ?? '';
  final msg = info.message.toLowerCase();
  if (code == 'user_already_exists' ||
      code == 'email_exists' ||
      code == 'identity_already_exists') {
    return true;
  }
  return msg.contains('already exists') ||
      msg.contains('already been registered') ||
      msg.contains('user already registered') ||
      msg.contains('creating identity') ||
      msg.contains('duplicate key') ||
      (msg.contains('unique') && msg.contains('identit'));
}
