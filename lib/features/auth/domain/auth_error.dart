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

/// Normalized `{ code, error/message }` from an Edge Function HTTP body.
class EdgeFunctionErrorPayload {
  const EdgeFunctionErrorPayload({this.code, this.message});

  final String? code;
  final String? message;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Reads `code` and user-facing error text from JSON maps, JSON strings, or
/// plain text returned on failed Edge Function calls.
EdgeFunctionErrorPayload parseEdgeFunctionError(Object? body) {
  if (body == null) return const EdgeFunctionErrorPayload();

  if (body is Map) {
    final codeRaw = body['code'];
    String? code;
    if (codeRaw is String) {
      code = _nonEmptyString(codeRaw);
    } else if (codeRaw is num) {
      code = codeRaw.toString();
    }
    final message = _nonEmptyString(body['error']) ??
        _nonEmptyString(body['message']) ??
        _nonEmptyString(body['msg']) ??
        _nonEmptyString(body['error_description']);
    return EdgeFunctionErrorPayload(code: code, message: message);
  }

  if (body is String) {
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return parseEdgeFunctionError(decoded);
        }
      } catch (_) {}
    }
    return EdgeFunctionErrorPayload(message: trimmed.isEmpty ? null : trimmed);
  }

  return EdgeFunctionErrorPayload(message: body.toString());
}

/// Safe, non-enumerating copy for wrong email/password (and unknown account).
const emailLoginIncorrectCredentialsMessage =
    'Incorrect email or password. Please try again.';

const emailLoginNetworkMessage =
    'Unable to connect. Check your internet connection and try again.';

const emailLoginRateLimitMessage =
    'Too many login attempts. Please wait a moment and try again.';

const emailLoginGenericFallbackMessage =
    'Something went wrong. Please try again.';

int? retryAfterSecondsFromErrorBody(Object? errorBody) {
  if (errorBody is! Map) return null;
  final raw = errorBody['retry_after_seconds'];
  if (raw is int) return raw > 0 ? raw : null;
  if (raw is num) {
    final n = raw.toInt();
    return n > 0 ? n : null;
  }
  return int.tryParse(raw?.toString() ?? '');
}

int? attemptsRemainingFromErrorBody(Object? errorBody) {
  if (errorBody is! Map) return null;
  final raw = errorBody['attempts_remaining'];
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is num) return raw.toInt().clamp(0, 99);
  return int.tryParse(raw?.toString() ?? '');
}

/// Admin portal wrong-password copy when the server reports remaining attempts.
String adminLoginInvalidCredentialsMessage(int attemptsRemaining) {
  if (attemptsRemaining <= 0) {
    return emailLoginIncorrectCredentialsMessage;
  }
  final n = attemptsRemaining;
  return 'Incorrect email or password.\n'
      '$n attempt${n == 1 ? '' : 's'} remaining.';
}

String adminLoginLockoutMessage(int retryAfterSeconds) {
  final seconds = retryAfterSeconds.clamp(1, 86400);
  if (seconds >= 60) {
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    if (rem == 0) {
      return 'Too many failed login attempts. Please try again in '
          '$minutes minute${minutes == 1 ? '' : 's'}.';
    }
    final mm = minutes.toString().padLeft(1, '0');
    final ss = rem.toString().padLeft(2, '0');
    return 'Too many failed login attempts. Please try again in $mm:$ss.';
  }
  return 'Too many failed login attempts. Please try again in '
      '$seconds second${seconds == 1 ? '' : 's'}.';
}

/// True when the sign-in request never reached the Edge Function (browser/network).
bool isEmailLoginTransportFailure({
  int? httpStatus,
  String? message,
  Object? errorBody,
  String? errorCode,
}) {
  final code = errorCode?.toLowerCase().trim();
  if (code == 'invalid_credentials' ||
      code == '401' ||
      code == 'admin_login_locked' ||
      code == 'turnstile_failed' ||
      code == 'turnstile_required' ||
      code == 'rate_limited' ||
      code == 'admin_access_denied') {
    return false;
  }

  if (httpStatus != null && httpStatus > 0) return false;

  if (_looksLikeTransportError(message)) return true;

  if (errorBody != null) {
    final fromBody = parseEdgeFunctionError(errorBody).message;
    if (_looksLikeTransportError(fromBody)) return true;
  }

  return false;
}

bool _looksLikeTransportError(String? message) {
  final msg = (message ?? '').toLowerCase();
  if (msg.isEmpty) return false;
  return msg.contains('failed to fetch') ||
      msg.contains('network error') ||
      msg.contains('networkrequestfailed') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('connection closed') ||
      msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('timed out') ||
      msg.contains('timeout') ||
      msg.contains('err_connection') ||
      msg.contains('failed host lookup') ||
      msg.contains('unable to resolve');
}

/// Central mapper for `sign-in-with-email` failures (HTTP body, status, transport).
String mapEmailLoginFailure({
  String? code,
  String? serverError,
  int? httpStatus,
  Object? errorBody,
  String? reasonPhrase,
  int? retryAfterSeconds,
}) {
  return emailLoginUiMessage(
    code: code,
    serverError: serverError ?? reasonPhrase,
    httpStatus: httpStatus,
    errorBody: errorBody,
    retryAfterSeconds: retryAfterSeconds,
  );
}

/// Maps `sign-in-with-email` Edge Function codes to user-facing copy.
String emailLoginUiMessage({
  String? code,
  String? serverError,
  int? httpStatus,
  Object? errorBody,
  int? retryAfterSeconds,
}) {
  final parsed = errorBody != null
      ? parseEdgeFunctionError(errorBody)
      : (serverError != null && serverError.trim().startsWith('{')
            ? parseEdgeFunctionError(serverError)
            : EdgeFunctionErrorPayload(code: code, message: serverError));

  final normalizedCode = (parsed.code ?? code)?.toLowerCase().trim();
  final resolvedError = parsed.message ?? serverError;
  final lockSeconds =
      retryAfterSeconds ?? retryAfterSecondsFromErrorBody(errorBody);
  final attemptsRemaining = attemptsRemainingFromErrorBody(errorBody);

  if (attemptsRemaining != null ||
      normalizedCode == 'invalid_credentials' ||
      normalizedCode == '401') {
    if (attemptsRemaining != null) {
      return adminLoginInvalidCredentialsMessage(attemptsRemaining);
    }
    return emailLoginIncorrectCredentialsMessage;
  }

  switch (normalizedCode) {
    case 'admin_login_locked':
      if (lockSeconds != null) {
        return adminLoginLockoutMessage(lockSeconds);
      }
      return 'Too many failed login attempts. Please try again in 5 minutes.';
    case 'admin_access_denied':
      return 'This account does not have admin access.';
    case 'invalid_credentials':
    case '401':
      final remaining = attemptsRemainingFromErrorBody(errorBody);
      if (remaining != null) {
        return adminLoginInvalidCredentialsMessage(remaining);
      }
      return emailLoginIncorrectCredentialsMessage;
    case 'turnstile_required':
      return 'Complete human verification before signing in.';
    case 'turnstile_failed':
      return resolvedError?.trim().isNotEmpty == true
          ? resolvedError!.trim()
          : 'Human verification failed. Please try again.';
    case 'rate_limited':
    case '429':
      return resolvedError?.trim().isNotEmpty == true
          ? _safeRateLimitCopy(resolvedError!.trim())
          : emailLoginRateLimitMessage;
    case 'unavailable':
    case '503':
      if (httpStatus == 401 || httpStatus == 403) {
        return emailLoginIncorrectCredentialsMessage;
      }
      return 'Sign-in is temporarily unavailable. Please try again.';
    case 'invalid_request':
    case '400':
      return resolvedError?.trim().isNotEmpty == true
          ? _safeInvalidRequestCopy(resolvedError!.trim())
          : 'Enter a valid email and password.';
    case 'email_not_confirmed':
      return 'Please confirm your email using the link we sent, '
          'then sign in again.';
  }

  if (isEmailLoginTransportFailure(
    httpStatus: httpStatus,
    message: resolvedError,
    errorBody: errorBody,
    errorCode: normalizedCode,
  )) {
    return emailLoginNetworkMessage;
  }

  final msg = (resolvedError ?? '').toLowerCase();
  if (msg.contains('invalid email or password') ||
      msg.contains('incorrect email or password') ||
      msg.contains('invalid login credentials') ||
      msg.contains('invalid_credentials')) {
    return emailLoginIncorrectCredentialsMessage;
  }
  if (msg.contains('email not confirmed')) {
    return 'Please confirm your email using the link we sent, '
        'then sign in again.';
  }
  if (msg.contains('human verification') ||
      msg.contains('verification failed') ||
      msg.contains('verification expired') ||
      (msg.contains('verification') && !msg.contains('email not confirmed'))) {
    return resolvedError!.trim();
  }
  if (msg.contains('too many')) {
    return _safeRateLimitCopy(resolvedError!.trim());
  }
  if (httpStatus == 401) {
    return emailLoginIncorrectCredentialsMessage;
  }
  if (httpStatus == 429) {
    return emailLoginRateLimitMessage;
  }
  if (httpStatus == 403 &&
      (msg.contains('verification') || msg.contains('captcha'))) {
    return resolvedError?.trim().isNotEmpty == true
        ? resolvedError!.trim()
        : 'Human verification failed. Please try again.';
  }
  return emailLoginGenericFallbackMessage;
}

String _safeRateLimitCopy(String serverText) {
  final lower = serverText.toLowerCase();
  if (lower.contains('too many') || lower.contains('wait')) {
    return serverText;
  }
  return emailLoginRateLimitMessage;
}

String _safeInvalidRequestCopy(String serverText) {
  final lower = serverText.toLowerCase();
  if (lower.contains('valid email')) {
    return 'Enter a valid email address.';
  }
  return serverText;
}

/// Maps GoTrue [AuthException] errors after direct auth calls (e.g. setSession).
String mapGoTrueEmailLoginFailure({String? code, required String message}) {
  final parsed = parseGoTrueError(code: code, message: message);
  return emailLoginUiMessage(
    code: parsed.code,
    serverError: parsed.message,
  );
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
