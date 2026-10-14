import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/controllers/admin_portal_session_controller.dart';
import 'package:thriftline/features/admin/domain/admin_portal_session_policy.dart';

void main() {
  group('adminPortalRemainingMs', () {
    test('returns full timeout when activity was just now', () {
      const now = 1_700_000_000_000;
      expect(
        adminPortalRemainingMs(lastActivityMs: now, nowMs: now),
        adminPortalInactivityTimeout.inMilliseconds,
      );
    });

    test('returns zero when idle beyond timeout', () {
      const last = 1_700_000_000_000;
      final now = last + adminPortalInactivityTimeout.inMilliseconds + 1;
      expect(adminPortalRemainingMs(lastActivityMs: last, nowMs: now), 0);
    });
  });

  group('adminPortalInactivityLogoutMessage', () {
    test('matches product copy', () {
      expect(
        adminPortalInactivityLogoutMessage,
        contains('10 minutes of inactivity'),
      );
    });
  });

  group('resolveAdminPortalMonitorStartMs', () {
    test('reuses a stored clock only for a restored session', () {
      expect(
        resolveAdminPortalMonitorStartMs(
          storedActivityMs: 100,
          nowMs: 999,
          reuseStoredActivity: true,
        ),
        100,
      );
    });

    test('starts a fresh clock after a new sign-in', () {
      expect(
        resolveAdminPortalMonitorStartMs(
          storedActivityMs: 100,
          nowMs: 999,
          reuseStoredActivity: false,
        ),
        999,
      );
    });

    test('starts now when no stored clock exists', () {
      expect(
        resolveAdminPortalMonitorStartMs(
          storedActivityMs: 0,
          nowMs: 999,
          reuseStoredActivity: true,
        ),
        999,
      );
    });
  });
}
