import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import 'admin_audit_log_models.dart';
import 'admin_dashboard_models.dart';

class AdminAuditListResult {
  const AdminAuditListResult({
    required this.rows,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AdminAuditLogRow> rows;
  final int total;
  final int limit;
  final int offset;
}

class AdminAuditService {
  AdminAuditService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminAuditListResult> list({
    String? search,
    String category = AdminAuditCategory.all,
    String status = AdminAuditStatusFilter.all,
    String? actorUserId,
    DateTime? from,
    DateTime? toExclusive,
    int limit = 25,
    int offset = 0,
  }) async {
    final raw = await _supabase.client.rpc(
      'list_admin_audit_logs',
      params: {
        'p_search': search?.trim().isEmpty ?? true ? null : search!.trim(),
        'p_category': category == AdminAuditCategory.all ? null : category,
        'p_status': status == AdminAuditStatusFilter.all ? null : status,
        'p_actor_user_id': actorUserId,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': toExclusive?.toUtc().toIso8601String(),
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    final map = supabaseRpcMap(raw) ?? {};
    final rowsRaw = map['rows'];
    final rows = <AdminAuditLogRow>[];
    if (rowsRaw is List) {
      for (final item in rowsRaw) {
        if (item is Map<String, dynamic>) {
          rows.add(AdminAuditLogRow.fromJson(item));
        } else if (item is Map) {
          rows.add(AdminAuditLogRow.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    int asInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return AdminAuditListResult(
      rows: rows,
      total: asInt(map['total'], rows.length),
      limit: asInt(map['limit'], limit),
      offset: asInt(map['offset'], offset),
    );
  }

  Future<void> record({
    required String category,
    required String eventType,
    required String status,
    required String summary,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _supabase.client.rpc(
        'record_admin_audit_log',
        params: {
          'p_category': category,
          'p_event_type': eventType,
          'p_status': status,
          'p_summary': summary,
          'p_target_type': targetType,
          'p_target_id': targetId,
          'p_details': details ?? {},
        },
      );
    } catch (e, st) {
      debugPrint('AdminAuditService.record error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  static AdminDateWindow? windowToQuery(AdminDateWindow? window) {
    return window;
  }
}
