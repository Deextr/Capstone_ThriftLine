import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../domain/admin_seller_payout.dart';
import 'financial_evidence_storage.dart';

class AdminSellerPayoutsService {
  AdminSellerPayoutsService(this._supabase)
    : evidence = FinancialEvidenceStorage(_supabase);

  final SupabaseService _supabase;
  final FinancialEvidenceStorage evidence;

  Future<AdminSellerPayoutPage> list({
    required AdminPayoutStatusFilter status,
    String search = '',
    required int limit,
    required int offset,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_list_seller_payouts',
      params: {
        'p_status': status.rpcValue,
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] != true) {
      throw StateError(
        supabaseRpcError(map, fallback: 'Unable to load payouts.') ??
            'Unable to load payouts.',
      );
    }
    final items = (map['items'] is List ? map['items'] as List : const [])
        .whereType<Map>()
        .map((m) => AdminSellerPayout.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    return AdminSellerPayoutPage(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
      counts: AdminSellerPayoutCounts.fromMap(supabaseRpcMap(map['counts'])),
    );
  }

  Future<int> waitingCount() async {
    final page = await list(
      status: AdminPayoutStatusFilter.requested,
      limit: 1,
      offset: 0,
    );
    return page.counts.requested;
  }

  Future<String?> markPaid({
    required String payoutId,
    required int transferredAmountCentavos,
    required String reference,
    required DateTime transferredAt,
    required String evidencePath,
    String? note,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_mark_seller_payout_paid',
      params: {
        'p_payout_id': payoutId,
        'p_transferred_amount_centavos': transferredAmountCentavos,
        'p_gcash_reference': reference.trim(),
        'p_transferred_at': transferredAt.toUtc().toIso8601String(),
        'p_evidence_path': evidencePath,
        'p_admin_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      },
    );
    if (supabaseRpcSuccess(raw)) return null;
    return supabaseRpcError(raw, fallback: 'Could not record this transfer.');
  }

  Future<String?> reject({
    required String payoutId,
    required String reason,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_reject_seller_payout',
      params: {'p_payout_id': payoutId, 'p_reason': reason.trim()},
    );
    if (supabaseRpcSuccess(raw)) return null;
    return supabaseRpcError(raw, fallback: 'Could not reject this payout.');
  }
}
