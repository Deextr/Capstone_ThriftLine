import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../auth/domain/auth_error.dart';
import 'admin_account_models.dart';

class AdminAccountService {
  AdminAccountService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminAccountPage> list({
    String search = '',
    String? status,
    String? role,
    int limit = 20,
    int offset = 0,
  }) async {
    final raw = await _supabase.client.rpc(
      'list_admin_accounts',
      params: {
        'p_search': search.trim(),
        'p_status': status,
        'p_role': role,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final map = supabaseRpcMap(raw) ?? const <String, dynamic>{};
    final rowsRaw = map['rows'];
    final rows = <AdminAccountRecord>[
      if (rowsRaw is List)
        for (final row in rowsRaw)
          if (row is Map)
            AdminAccountRecord.fromJson(Map<String, dynamic>.from(row)),
    ];
    final total = map['total'];
    return AdminAccountPage(
      rows: rows,
      total: total is int
          ? total
          : int.tryParse(total?.toString() ?? '') ?? rows.length,
      counts: AdminAccountCounts.fromJson(supabaseRpcMap(map['counts'])),
    );
  }

  Future<AdminInviteResult> create({
    required String fullName,
    required String email,
  }) {
    return _invoke({
      'action': 'create',
      'full_name': fullName.trim(),
      'email': normalizeAdminEmail(email),
    });
  }

  Future<AdminInviteResult> resend(String invitationId) {
    return _invoke({'action': 'resend', 'invitation_id': invitationId});
  }

  Future<AdminInviteResult> revoke(String invitationId) {
    return _invoke({
      'action': 'revoke_invitation',
      'invitation_id': invitationId,
    });
  }

  Future<AdminInviteResult> setActive({
    required String userId,
    required bool active,
  }) {
    return _invoke({
      'action': active ? 'reactivate' : 'deactivate',
      'user_id': userId,
    });
  }

  Future<String?> completeInvitation() async {
    try {
      await _supabase.client.rpc('complete_admin_invitation');
      return null;
    } catch (e) {
      debugPrint('complete_admin_invitation error: $e');
      final text = e.toString().toLowerCase();
      if (text.contains('expired')) {
        return 'This invitation has expired. Ask a Super Admin to resend it.';
      }
      if (text.contains('invalid') || text.contains('used')) {
        return 'This invitation link is invalid or has already been used.';
      }
      return 'Could not finish account setup. Try the invitation link again.';
    }
  }

  Future<AdminInviteResult> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.client.functions.invoke(
        'invite-admin',
        body: body,
      );
      final data = response.data;
      if (response.status >= 400) {
        return _fromBody(data);
      }
      final map = supabaseRpcMap(data);
      return AdminInviteResult(
        ok: map?['ok'] == true || response.status < 400,
        invitationId: map?['invitation_id']?.toString(),
      );
    } on FunctionException catch (e) {
      debugPrint(
        'invite-admin FunctionException status=${e.status} details=${e.details}',
      );
      return _fromBody(e.details);
    } catch (e) {
      debugPrint('invite-admin error: $e');
      return const AdminInviteResult(
        ok: false,
        message:
            'Could not reach the server. Check your connection and try again.',
        code: 'network',
      );
    }
  }

  AdminInviteResult _fromBody(Object? body) {
    final payload = parseEdgeFunctionError(body);
    final map = body is Map ? Map<String, dynamic>.from(body) : null;
    return AdminInviteResult(
      ok: false,
      code: payload.code ?? map?['code']?.toString(),
      message: adminInviteFailureMessage(
        code: payload.code ?? map?['code']?.toString(),
        serverMessage: payload.message,
      ),
      invitationId: map?['invitation_id']?.toString(),
    );
  }
}
