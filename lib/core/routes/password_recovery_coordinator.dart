import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/password_recovery_link.dart';
import '../config/supabase_config.dart';

/// Parses password-recovery deep links and exchanges them for a recovery session.
class PasswordRecoveryCoordinator extends ChangeNotifier {
  PasswordRecoveryCoordinator({
    Future<void> Function()? onRecoveryLinkAccepted,
    Future<void> Function()? onRecoveryLinkFailed,
  }) : _onRecoveryLinkAccepted = onRecoveryLinkAccepted,
       _onRecoveryLinkFailed = onRecoveryLinkFailed;

  final Future<void> Function()? _onRecoveryLinkAccepted;
  final Future<void> Function()? _onRecoveryLinkFailed;

  String? _linkError;
  bool _busy = false;
  bool _sessionReady = false;

  /// User-facing error when the recovery link is invalid or expired.
  String? get linkError => _linkError;

  void clearLinkError() {
    if (_linkError == null) return;
    _linkError = null;
    notifyListeners();
  }

  Future<void> accept(Uri uri) async {
    if (!PasswordRecoveryLink.isRecoveryUri(uri) &&
        !PasswordRecoveryLink.hasRecoveryCallbackParams(uri)) {
      return;
    }
    if (_busy || _sessionReady) return;
    _busy = true;
    await _onRecoveryLinkAccepted?.call();
    final callback = PasswordRecoveryLink.normalizeCallbackUri(uri);
    debugPrint(
      'Password recovery accept: token_hash='
      '${PasswordRecoveryLink.recoveryTokenHash(callback) != null} '
      'code=${callback.queryParameters.containsKey('code')} '
      'access_token=${callback.queryParameters.containsKey('access_token')}',
    );
    try {
      final tokenHash = PasswordRecoveryLink.recoveryTokenHash(callback);
      if (tokenHash != null &&
          !callback.queryParameters.containsKey('access_token') &&
          !callback.queryParameters.containsKey('code')) {
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
        await SupabaseConfig.client.auth.getSessionFromUrl(callback);
      }
      _sessionReady = true;
      _linkError = null;
    } on AuthException catch (e) {
      debugPrint(
        'Password recovery link failed: code=${e.code} status=${e.statusCode}',
      );
      _linkError = _recoveryLinkErrorMessage(e);
    } catch (e, stackTrace) {
      debugPrint('Password recovery link failed');
      debugPrintStack(stackTrace: stackTrace);
      _linkError =
          'This reset link is invalid or has expired. '
          'Request a new one from the login screen.';
    } finally {
      _busy = false;
      if (_linkError != null && !_sessionReady) {
        await _onRecoveryLinkFailed?.call();
      }
    }
    notifyListeners();
  }

  void resetForNewAttempt() {
    _sessionReady = false;
    _linkError = null;
    _busy = false;
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
