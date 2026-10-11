import 'dart:async';

bool isAdminAuthorizationFailure(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('42501') ||
      text.contains('super admin access required') ||
      text.contains('admin access required') ||
      text.contains('only an admin');
}

/// Refreshes the signed-in profile after a privileged call is rejected, so
/// the admin router can leave the portal when access has been removed.
class AdminPortalSession {
  static Future<void> Function()? refresh;

  static void note(Object error) {
    if (!isAdminAuthorizationFailure(error)) return;
    final action = refresh;
    if (action == null) return;
    unawaited(action());
  }

  static void noteCode(String? code) {
    if (code == 'forbidden') {
      note('super admin access required');
    }
  }
}
