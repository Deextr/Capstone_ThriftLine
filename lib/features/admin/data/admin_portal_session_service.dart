import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

/// Result of syncing the server-side portal idle session row.
class AdminPortalSessionSyncResult {
  const AdminPortalSessionSyncResult._({
    required this.ok,
    required this.transientFailure,
  });

  const AdminPortalSessionSyncResult.ok()
    : this._(ok: true, transientFailure: false);

  const AdminPortalSessionSyncResult.transient()
    : this._(ok: false, transientFailure: true);

  const AdminPortalSessionSyncResult.inactive()
    : this._(ok: false, transientFailure: false);

  final bool ok;
  final bool transientFailure;

  /// RPC `{success:false}` is only idle-inactive when the server says so.
  /// Missing functions, forbidden, or unexpected payloads must not log anyone out.
  factory AdminPortalSessionSyncResult.fromRpc(dynamic raw) {
    final map = supabaseRpcMap(raw);
    if (map == null) return const AdminPortalSessionSyncResult.transient();
    if (map['success'] == true) return const AdminPortalSessionSyncResult.ok();
    final error = map['error']?.toString().trim().toLowerCase() ?? '';
    if (error == 'portal_session_inactive') {
      return const AdminPortalSessionSyncResult.inactive();
    }
    return const AdminPortalSessionSyncResult.transient();
  }
}

/// Server-side Admin Web Portal idle session (activity touch, begin, revoke).
class AdminPortalSessionService {
  AdminPortalSessionService(this._supabase);

  final SupabaseService _supabase;

  Future<bool> begin() => _ok('admin_portal_session_begin');

  Future<bool> touch() => _ok('admin_portal_session_touch');

  /// Refreshes activity, or creates/reopens the portal session row if needed.
  Future<AdminPortalSessionSyncResult> ensureLive() async {
    final touched = await _invoke('admin_portal_session_touch');
    if (touched.ok) return AdminPortalSessionSyncResult.ok();
    if (touched.transientFailure) {
      return const AdminPortalSessionSyncResult.transient();
    }
    final began = await _invoke('admin_portal_session_begin');
    if (began.ok) return AdminPortalSessionSyncResult.ok();
    if (began.transientFailure) {
      return const AdminPortalSessionSyncResult.transient();
    }
    return const AdminPortalSessionSyncResult.inactive();
  }

  Future<bool> revoke({String reason = 'manual'}) async {
    try {
      final raw = await _supabase.client.rpc(
        'admin_portal_session_revoke',
        params: {'p_reason': reason},
      );
      final map = supabaseRpcMap(raw);
      return map?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ok(String fn) async {
    final result = await _invoke(fn);
    return result.ok;
  }

  Future<({bool ok, bool transientFailure})> _invoke(String fn) async {
    try {
      final result = AdminPortalSessionSyncResult.fromRpc(
        await _supabase.client.rpc(fn),
      );
      return (ok: result.ok, transientFailure: result.transientFailure);
    } catch (_) {
      return (ok: false, transientFailure: true);
    }
  }
}
