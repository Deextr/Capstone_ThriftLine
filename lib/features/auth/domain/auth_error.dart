import 'dart:convert';

/// Normalized GoTrue error. Some 500s put `code` and `message` inside a JSON
/// string, so [AuthException.code] is empty and the UI falls through to a
/// generic "Something went wrong".
class GoTrueErrorInfo {
  const GoTrueErrorInfo({this.code, required this.message});

  final String? code;
  final String message;
}

GoTrueErrorInfo parseGoTrueError({
  String? code,
  required String message,
}) {
  var resolvedCode =
      (code == null || code.isEmpty || code == '-') ? null : code;
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
