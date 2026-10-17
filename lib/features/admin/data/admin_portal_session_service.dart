import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

/// Server-side Admin Web Portal idle session (activity touch, begin, revoke).
class AdminPortalSessionService {
  AdminPortalSessionService(this._supabase);

  final SupabaseService _supabase;

  Future<bool> begin() => _ok('admin_portal_session_begin');

  Future<bool> touch() => _ok('admin_portal_session_touch');

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
    try {
      final raw = await _supabase.client.rpc(fn);
      final map = supabaseRpcMap(raw);
      return map?['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
