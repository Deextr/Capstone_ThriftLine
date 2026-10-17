import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

/// Resolves a Supabase client after admin portal access checks.
Future<SupabaseClient> resolveAdminClient(SupabaseService supabase) async {
  await supabase.adminQueryPrepare?.call();
  return supabase.client;
}

/// Prepares the server-side admin portal session and validates [is_admin()] before queries.
class AdminPortalDataAccess {
  AdminPortalDataAccess(this._supabase);

  final SupabaseService _supabase;

  static AdminPortalDataAccess? _bound;

  static void bind(SupabaseService supabase) {
    _bound = AdminPortalDataAccess(supabase);
    supabase.adminQueryPrepare = _bound!.ensureReady;
  }

  static AdminPortalDataAccess? get bound => _bound;

  /// Runs [action] after [ensureReady]. Used by all admin data services.
  Future<T> run<T>(Future<T> Function(SupabaseClient client) action) async {
    await ensureReady();
    return action(_supabase.client);
  }

  Future<void> ensureReady() async {
    if (!_supabase.isAuthenticated) {
      throw AdminPortalAccessException('Sign in to the admin portal.');
    }

    await _syncPortalSession();
    await _claimAndSyncEmailGate();

    final status = await _readAccessStatus();
    if (status == null) {
      throw AdminPortalAccessException(
        'Admin database is missing access helpers. Run migration '
        '20261017290000_admin_portal_access_repair.sql on Supabase, then retry.',
        code: 'migration_required',
      );
    }

    if (status['is_admin'] == true) {
      return;
    }

    if (status['active_admin'] != true) {
      throw AdminPortalAccessException(
        'This account is not an active administrator.',
      );
    }

    if (status['email_gate'] != true) {
      throw AdminPortalAccessException(
        'This admin session is not verified for marketplace access. '
        'Sign out, sign in, and enter the email code, then retry.',
        code: AdminPortalAccessException.emailOtpRequired,
      );
    }

    if (status['portal_session_live'] != true) {
      throw AdminPortalAccessException(
        'Your admin session expired. Sign in again.',
        code: AdminPortalAccessException.sessionExpired,
      );
    }

    throw AdminPortalAccessException(
      'Admin access is not available for this session.',
    );
  }

  Future<void> _claimAndSyncEmailGate() async {
    try {
      await _supabase.client.rpc('claim_email_login_session_gate_after_otp');
    } catch (e) {
      debugPrint('AdminPortalDataAccess claim email gate: $e');
    }
    try {
      await _supabase.client.rpc('sync_email_login_session_gate_from_verified');
    } catch (e) {
      debugPrint('AdminPortalDataAccess sync email gate: $e');
    }
  }

  Future<void> _syncPortalSession() async {
    try {
      final begin = supabaseRpcMap(
        await _supabase.client.rpc('admin_portal_session_begin'),
      );
      if (begin?['success'] == true) return;

      await _supabase.client.rpc('admin_portal_session_touch');
    } catch (e) {
      debugPrint('AdminPortalDataAccess portal session sync: $e');
    }
  }

  Future<Map<String, dynamic>?> _readAccessStatus() async {
    try {
      final raw = await _supabase.client.rpc('admin_portal_access_status');
      return supabaseRpcMap(raw);
    } catch (e) {
      debugPrint('AdminPortalDataAccess status RPC unavailable: $e');
      return null;
    }
  }
}

class AdminPortalAccessException implements Exception {
  AdminPortalAccessException(this.message, {this.code});

  static const emailOtpRequired = 'email_otp_required';
  static const sessionExpired = 'session_expired';

  final String message;
  final String? code;

  @override
  String toString() => message;
}

String adminPortalAccessUserMessage(Object error) {
  if (error is AdminPortalAccessException) return error.message;
  final text = error.toString();
  if (text.contains('Only an admin can view')) {
    return 'Administrator access required. Complete email verification or sign in again.';
  }
  if (text.contains('JWT expired') || text.contains('Invalid Refresh Token')) {
    return 'Your session expired. Sign in again.';
  }
  final fromRpc = RegExp(
    r'StateError: (.+)',
  ).firstMatch(text)?.group(1)?.trim();
  if (fromRpc != null && fromRpc.isNotEmpty) return fromRpc;
  return 'Could not load admin data. Try again.';
}
