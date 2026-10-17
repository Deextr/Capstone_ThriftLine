import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../domain/admin_buyer_refund.dart';
import '../domain/admin_refund.dart';
import 'delivery_payment_hold.dart';
import 'financial_evidence_storage.dart';

class AdminRefundSnapshot {
  const AdminRefundSnapshot({
    required this.hold,
    required this.details,
    required this.attempts,
  });

  final DeliveryPaymentHold? hold;
  final AdminRefundDetails? details;
  final List<AdminRefundAttempt> attempts;
}

class AdminRefundsService {
  AdminRefundsService(this._supabase)
    : evidence = FinancialEvidenceStorage(_supabase);

  final SupabaseService _supabase;
  final FinancialEvidenceStorage evidence;

  Future<AdminBuyerRefundPage> list({
    required AdminBuyerRefundStatusFilter status,
    String search = '',
    required int limit,
    required int offset,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_list_buyer_refunds',
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
        supabaseRpcError(map, fallback: 'Unable to load buyer refunds.') ??
            'Unable to load buyer refunds.',
      );
    }
    final items = (map['items'] is List ? map['items'] as List : const [])
        .whereType<Map>()
        .map((m) => AdminBuyerRefundRow.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    return AdminBuyerRefundPage(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
      counts: AdminBuyerRefundCounts.fromMap(supabaseRpcMap(map['counts'])),
    );
  }

  Future<int> needsActionCount() async {
    final page = await list(
      status: AdminBuyerRefundStatusFilter.needsAction,
      limit: 1,
      offset: 0,
    );
    return page.counts.needsAction;
  }

  Future<AdminRefundSnapshot> load(String escrowId) async {
    final escrowRow = await _supabase.client
        .from('escrow')
        .select('*')
        .eq('escrow_id', escrowId)
        .maybeSingle();
    final detailsRow = await _supabase.client
        .from('escrow_refund_details')
        .select(
          'transfer_link, transfer_link_expires_at, gcash_account_name, '
          'gcash_mobile_number, gcash_submitted_at, manual_amount_centavos, '
          'manual_reference, manual_sent_at, manual_evidence_path, '
          'manual_note, manual_recorded_at',
        )
        .eq('escrow_id', escrowId)
        .maybeSingle();
    final attemptRows = await _supabase.client
        .from('escrow_refund_attempts')
        .select(
          'created_at, source, action, outcome, paymongo_refund_id, '
          'http_status, provider_status, error_code',
        )
        .eq('escrow_id', escrowId)
        .order('created_at', ascending: false)
        .limit(20);
    return AdminRefundSnapshot(
      hold: escrowRow == null
          ? null
          : DeliveryPaymentHold.fromSupabase(
              Map<String, dynamic>.from(escrowRow),
            ),
      details: detailsRow == null
          ? null
          : AdminRefundDetails.fromMap(Map<String, dynamic>.from(detailsRow)),
      attempts: [
        for (final row in attemptRows)
          AdminRefundAttempt.fromMap(Map<String, dynamic>.from(row)),
      ],
    );
  }

  /// `check` reads PayMongo; `retry` asks PayMongo for a new refund.
  Future<AdminRefundActionResult> reconcile({
    required String escrowId,
    required String action,
  }) async {
    try {
      final response = await _supabase.client.functions.invoke(
        'reconcile-refund',
        body: {'escrow_id': escrowId, 'action': action},
      );
      return adminRefundActionResultFromMap(
        supabaseRpcMap(response.data),
        action: action,
      );
    } on FunctionException catch (e) {
      return adminRefundActionResultFromMap(
        _functionErrorMap(e),
        action: action,
      );
    }
  }

  Future<String?> recordManualRefund({
    required String escrowId,
    required int amountCentavos,
    required String reference,
    required DateTime sentAt,
    required String evidencePath,
    required String accountName,
    required String mobileNumber,
    String? note,
  }) async {
    final raw = await _supabase.client.rpc(
      'admin_record_manual_refund',
      params: {
        'p_escrow_id': escrowId,
        'p_amount_centavos': amountCentavos,
        'p_reference': reference.trim(),
        'p_sent_at': sentAt.toUtc().toIso8601String(),
        'p_evidence_path': evidencePath,
        'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'p_gcash_account_name': accountName.trim(),
        'p_gcash_mobile_number': mobileNumber,
      },
    );
    if (supabaseRpcSuccess(raw)) return null;
    return supabaseRpcError(raw, fallback: 'Could not record this refund.');
  }

  Map<String, dynamic>? _functionErrorMap(FunctionException error) {
    final details = error.details;
    if (details is Map) return supabaseRpcMap(details);
    if (details is String && details.trim().isNotEmpty) {
      try {
        return supabaseRpcMap(jsonDecode(details));
      } catch (_) {}
    }
    return null;
  }
}
