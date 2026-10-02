import '../../../core/routes/route_names.dart';

const kThriftlineAppScheme = 'thriftline';
const kPasswordRecoveryHost = 'reset-password';
const kPasswordRecoveryReturnPath = 'password-recovery-return';
const kPasswordRecoveryOpenPage = 'open-thriftline';

/// Deep link Supabase uses to return users into the app after email reset.
abstract final class PasswordRecoveryLink {
  static const redirectUrl = '$kThriftlineAppScheme://$kPasswordRecoveryHost';

  /// Hashed recovery token carried on the app deep link. Null for browser
  /// redirects that still use [getSessionFromUrl].
  static String? recoveryTokenHash(Uri? uri) {
    if (!isRecoveryUri(uri)) return null;
    final value = uri!.queryParameters['token_hash']?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static bool isRecoveryUri(Uri? uri) {
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (scheme == kThriftlineAppScheme &&
        (host == kPasswordRecoveryHost ||
            path.contains(kPasswordRecoveryHost))) {
      return true;
    }
    if ((scheme == 'https' || scheme == 'http') &&
        (path.contains(kPasswordRecoveryHost) ||
            path.contains(kPasswordRecoveryReturnPath) ||
            path.contains(kPasswordRecoveryOpenPage))) {
      return true;
    }
    return false;
  }

  /// Session tokens on a recovery deep link (query or fragment).
  static bool hasRecoveryCallbackParams(Uri uri) {
    if (!isRecoveryUri(uri)) return false;
    final fromFragment = Uri.splitQueryString(uri.fragment);
    const keys = ['access_token', 'code', 'token_hash', 'type'];
    for (final key in keys) {
      if (uri.queryParameters.containsKey(key) ||
          fromFragment.containsKey(key)) {
        return true;
      }
    }
    return uri.toString().contains('#access_token=') ||
        uri.toString().contains('?access_token=') ||
        uri.toString().contains('token_hash=');
  }

  /// Android often drops the URI fragment; merge hash into query for GoTrue.
  static Uri normalizeCallbackUri(Uri uri) {
    if (!isRecoveryUri(uri)) return uri;
    final merged = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      merged.addAll(Uri.splitQueryString(uri.fragment));
    } else {
      final raw = uri.toString();
      final hashIndex = raw.indexOf('#');
      if (hashIndex >= 0) {
        merged.addAll(Uri.splitQueryString(raw.substring(hashIndex + 1)));
      }
    }
    if (merged.isEmpty) return uri;
    return uri.replace(queryParameters: merged, fragment: '');
  }

  static String get resetPasswordRoute => RouteNames.resetPassword;
}
