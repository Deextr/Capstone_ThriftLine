import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../domain/confirmed_violation.dart';

class ConfirmedViolationsService {
  ConfirmedViolationsService(this._supabase);

  final SupabaseService _supabase;

  Future<List<ConfirmedViolationSummary>> listMine() async {
    final dynamic rpcRes;
    try {
      rpcRes = await _supabase.client.rpc('list_my_confirmed_violations');
    } on PostgrestException catch (e) {
      throw StateError(
        e.message.trim().isNotEmpty
            ? e.message
            : 'Unable to load confirmed violations.',
      );
    }
    if (!supabaseRpcSuccess(rpcRes)) {
      throw StateError(
        supabaseRpcError(
              rpcRes,
              fallback: 'Unable to load confirmed violations.',
            ) ??
            'Unable to load confirmed violations.',
      );
    }
    final map = supabaseRpcMap(rpcRes) ?? const {};
    final raw = map['violations'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => ConfirmedViolationSummary.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .where((item) => item.recordId.isNotEmpty && item.source.isNotEmpty)
        .toList();
  }

  Future<ConfirmedViolationDetail> loadDetail({
    required String source,
    required String recordId,
  }) async {
    final dynamic rpcRes;
    try {
      rpcRes = await _supabase.client.rpc(
        'get_my_confirmed_violation',
        params: {'p_source': source, 'p_record_id': recordId},
      );
    } on PostgrestException catch (e) {
      throw StateError(
        e.message.trim().isNotEmpty ? e.message : 'Violation not found.',
      );
    }
    if (!supabaseRpcSuccess(rpcRes)) {
      throw StateError(
        supabaseRpcError(rpcRes, fallback: 'Violation not found.') ??
            'Violation not found.',
      );
    }
    final map = supabaseRpcMap(rpcRes);
    if (map == null || map['record_id'] == null) {
      throw StateError('Violation not found.');
    }
    return ConfirmedViolationDetail.fromMap(map);
  }
}
