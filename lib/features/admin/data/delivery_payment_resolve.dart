import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

class DeliveryPaymentResult {
  const DeliveryPaymentResult({
    required this.success,
    this.alreadyDecided = false,
    this.decision,
    this.status,
    this.refundProvider,
    this.amountCentavos,
    this.error,
  });

  final bool success;
  final bool alreadyDecided;
  final String? decision;
  final String? status;
  final String? refundProvider;
  final int? amountCentavos;
  final String? error;

  factory DeliveryPaymentResult.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const DeliveryPaymentResult(
        success: false,
        error: 'Could not update this payment.',
      );
    }
    int? asCentavos(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '');
    }

    return DeliveryPaymentResult(
      success: map['success'] == true,
      alreadyDecided: map['already_decided'] == true,
      decision: map['decision']?.toString(),
      status: map['status']?.toString(),
      refundProvider: map['refund_provider']?.toString(),
      amountCentavos: asCentavos(map['amount_centavos']),
      error: map['error']?.toString(),
    );
  }
}

Future<DeliveryPaymentResult> resolveDeliveryRelease(
  SupabaseService supabase, {
  required String disputeId,
  String? adminNote,
}) async {
  try {
    final rpcRes = await supabase.client.rpc(
      'resolve_delivery_payment',
      params: {
        'p_dispute_id': disputeId,
        'p_decision': 'release',
        'p_admin_note': adminNote?.trim(),
      },
    );
    return DeliveryPaymentResult.fromMap(supabaseRpcMap(rpcRes));
  } catch (_) {
    return const DeliveryPaymentResult(
      success: false,
      error: 'Could not release this payment.',
    );
  }
}

Future<DeliveryPaymentResult> resolveDeliveryRefund(
  SupabaseService supabase, {
  required String disputeId,
  String? adminNote,
}) async {
  try {
    final response = await supabase.client.functions.invoke(
      'resolve-delivery-payment',
      body: {
        'dispute_id': disputeId,
        if (adminNote != null && adminNote.trim().isNotEmpty)
          'admin_note': adminNote.trim(),
      },
    );
    return DeliveryPaymentResult.fromMap(supabaseRpcMap(response.data));
  } on FunctionException catch (e) {
    return DeliveryPaymentResult.fromMap(_functionExceptionMap(e));
  } catch (_) {
    return const DeliveryPaymentResult(
      success: false,
      error: 'Could not refund this payment.',
    );
  }
}

Map<String, dynamic>? _functionExceptionMap(FunctionException error) {
  final details = error.details;
  if (details is Map) return supabaseRpcMap(details);
  if (details is String && details.trim().isNotEmpty) {
    try {
      return supabaseRpcMap(jsonDecode(details));
    } catch (_) {}
  }
  return {'success': false, 'error': 'Could not refund this payment.'};
}
