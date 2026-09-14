import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import 'seller_earnings.dart';

class SellerEarningsService {
  SellerEarningsService(this._supabase);

  final SupabaseService _supabase;

  Future<SellerEarningsSnapshot> loadSnapshot() async {
    final rpcRes = await _supabase.client.rpc('seller_earnings_snapshot');
    if (!supabaseRpcSuccess(rpcRes)) {
      throw StateError(
        supabaseRpcError(rpcRes, fallback: 'Unable to load earnings.') ??
            'Unable to load earnings.',
      );
    }
    return SellerEarningsSnapshot.fromMap(supabaseRpcMap(rpcRes) ?? const {});
  }

  Future<String?> requestPayout({int? amountCentavos}) async {
    try {
      final rpcRes = await _supabase.client.rpc(
        'request_seller_payout',
        params: {'p_amount_centavos': amountCentavos},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not record that payout request.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('request_seller_payout error: $e');
      return 'Could not record that payout request.';
    }
  }
}
