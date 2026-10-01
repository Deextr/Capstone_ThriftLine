import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/password_recovery_link.dart';
import '../config/supabase_config.dart';

/// Parses password-recovery deep links and exchanges them for a recovery session.
class PasswordRecoveryCoordinator extends ChangeNotifier {
  String? _linkError;

  /// User-facing error when the recovery link is invalid or expired.
  String? get linkError => _linkError;

  void clearLinkError() {
    if (_linkError == null) return;
    _linkError = null;
    notifyListeners();
  }

  Future<void> accept(Uri uri) async {
    if (!PasswordRecoveryLink.isRecoveryUri(uri)) return;
    try {
      final tokenHash = PasswordRecoveryLink.recoveryTokenHash(uri);
      if (tokenHash != null) {
        final response = await SupabaseConfig.client.auth.verifyOTP(
          type: OtpType.recovery,
          tokenHash: tokenHash,
        );
        if (response.session == null) {
          _linkError =
              'This reset link is invalid or has expired. '
              'Request a new one from the login screen.';
          notifyListeners();
          return;
        }
      } else {
        await SupabaseConfig.client.auth.getSessionFromUrl(uri);
      }
      _linkError = null;
    } on AuthException catch (e) {
      debugPrint(
        'Password recovery link failed: '
        'code=${e.code} status=${e.statusCode} "${e.message}"',
      );
      _linkError = _recoveryLinkErrorMessage(e);
    } catch (e, stackTrace) {
      debugPrint('Password recovery link unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      _linkError =
          'This reset link is invalid or has expired. '
          'Request a new one from the login screen.';
    }
    notifyListeners();
  }
}

String _recoveryLinkErrorMessage(AuthException e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('expired') ||
      msg.contains('invalid') ||
      msg.contains('otp') ||
      e.code == 'otp_expired') {
    return 'This reset link has expired or was already used. '
        'Request a new password reset email.';
  }
  if (msg.contains('access denied') || msg.contains('forbidden')) {
    return 'We could not verify this reset link. '
        'Request a new password reset email.';
  }
  return 'This reset link is invalid or has expired. '
      'Request a new one from the login screen.';
}

Future<void> attachPasswordRecoveryLinks(
  PasswordRecoveryCoordinator coordinator,
) async {
  final appLinks = AppLinks();
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null) await coordinator.accept(initial);
  } catch (e) {
    debugPrint('Password recovery initial link error: $e');
  }
  appLinks.uriLinkStream.listen(
    (uri) => coordinator.accept(uri),
    onError: (Object e) {
      debugPrint('Password recovery link stream error: $e');
    },
  );
}
