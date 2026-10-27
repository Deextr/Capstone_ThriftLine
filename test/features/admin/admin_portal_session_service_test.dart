import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_portal_session_service.dart';

void main() {
  group('AdminPortalSessionSyncResult', () {
    test('transient failures are distinct from inactive sessions', () {
      expect(
        const AdminPortalSessionSyncResult.transient().transientFailure,
        isTrue,
      );
      expect(const AdminPortalSessionSyncResult.transient().ok, isFalse);
      expect(
        const AdminPortalSessionSyncResult.inactive().transientFailure,
        isFalse,
      );
    });

    test('success payload is ok', () {
      final result = AdminPortalSessionSyncResult.fromRpc({
        'success': true,
      });
      expect(result.ok, isTrue);
    });

    test('portal_session_inactive is the only idle failure', () {
      final result = AdminPortalSessionSyncResult.fromRpc({
        'success': false,
        'error': 'portal_session_inactive',
      });
      expect(result.ok, isFalse);
      expect(result.transientFailure, isFalse);
    });

    test('forbidden or unexpected RPC payloads are transient', () {
      expect(
        AdminPortalSessionSyncResult.fromRpc({
          'success': false,
          'error': 'forbidden',
        }).transientFailure,
        isTrue,
      );
      expect(AdminPortalSessionSyncResult.fromRpc(null).transientFailure, isTrue);
      expect(AdminPortalSessionSyncResult.fromRpc('nope').transientFailure, isTrue);
    });
  });
}
