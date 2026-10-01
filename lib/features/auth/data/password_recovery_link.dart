import '../../../core/routes/route_names.dart';

const kThriftlineAppScheme = 'thriftline';
const kPasswordRecoveryHost = 'reset-password';

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
        path.contains(kPasswordRecoveryHost)) {
      return true;
    }
    return false;
  }

  static String get resetPasswordRoute => RouteNames.resetPassword;
}
