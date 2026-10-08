import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../auth/domain/auth_error.dart';
import 'checkout_payment_errors.dart';

/// Result of verifying a PayMongo app return. The redirect itself is not proof.
enum PaymongoAppReturnResult { paid, pending, failed }

class PaymongoCheckoutResult {
  const PaymongoCheckoutResult({
    required this.success,
    this.alreadyPaid = false,
    this.checkoutUrl,
    this.sessionId,
    this.error,
  });

  final bool success;
  final bool alreadyPaid;
  final String? checkoutUrl;
  final String? sessionId;
  final String? error;

  factory PaymongoCheckoutResult.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const PaymongoCheckoutResult(
        success: false,
        error: 'Unable to start payment right now. Please try again.',
      );
    }
    final error = map['error']?.toString().trim();
    final checkoutUrl = map['checkout_url']?.toString().trim();
    return PaymongoCheckoutResult(
      success: map['success'] == true,
      alreadyPaid: map['already_paid'] == true,
      checkoutUrl: checkoutUrl != null && checkoutUrl.isNotEmpty
          ? checkoutUrl
          : null,
      sessionId: map['session_id']?.toString(),
      error: error != null && error.isNotEmpty ? error : null,
    );
  }
}

bool isSafePaymongoCheckoutUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isScheme('https')) return false;
  return uri.host == 'checkout.paymongo.com' ||
      uri.host.endsWith('.paymongo.com');
}

const kPaymongoChannels = <String>['card', 'gcash'];

String? parsePaymongoChannel(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == 'card' || value == 'gcash') return value;
  return null;
}

String paymongoChannelLabel(String channel) => switch (channel) {
  'card' => 'Credit / Debit Card',
  'gcash' => 'GCash',
  _ => 'PayMongo',
};

String paymongoChannelCategory(String channel) => switch (channel) {
  'card' => 'Cards',
  'gcash' => 'E-Wallets',
  _ => 'Payment',
};

class PaymongoReconcileResult {
  const PaymongoReconcileResult({required this.outcome, this.error});

  final String outcome;
  final String? error;

  bool get isPaid => outcome == 'paid';
  bool get isPending => outcome == 'pending';
  bool get isExpired => outcome == 'expired';
  bool get isFailed => outcome == 'failed' || outcome == 'cancelled';
  bool get isUnsuccessful => isExpired || isFailed;

  factory PaymongoReconcileResult.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const PaymongoReconcileResult(
        outcome: 'pending',
        error: 'Unable to confirm payment status right now.',
      );
    }
    final err = map['error']?.toString().trim();
    var outcome = (map['outcome'] ?? '').toString().trim().toLowerCase();
    final voidMap = supabaseRpcMap(map['void']);
    if (outcome == 'pending' && voidMap != null && voidMap['success'] == true) {
      outcome = 'failed';
    }
    final allowed = {'paid', 'pending', 'expired', 'failed', 'cancelled'};
    return PaymongoReconcileResult(
      outcome: allowed.contains(outcome) ? outcome : 'pending',
      error: err != null && err.isNotEmpty ? err : null,
    );
  }

  factory PaymongoReconcileResult.fromFinalizeRpc(Map<String, dynamic>? map) {
    if (map == null || map['success'] != true) {
      final err = supabaseRpcError(
        map,
        fallback: 'Unable to finalize checkout.',
      );
      return PaymongoReconcileResult(outcome: 'pending', error: err);
    }
    final outcome = (map['outcome'] ?? 'pending')
        .toString()
        .trim()
        .toLowerCase();
    return PaymongoReconcileResult(outcome: outcome);
  }
}

Future<PaymongoReconcileResult> reconcilePaymongoCheckout(
  SupabaseService supabase, {
  required String orderId,
}) async {
  try {
    final response = await supabase.client.functions
        .invoke('reconcile-paymongo-checkout', body: {'order_id': orderId})
        .timeout(const Duration(seconds: 12));
    return PaymongoReconcileResult.fromMap(supabaseRpcMap(response.data));
  } on FunctionException catch (e) {
    return PaymongoReconcileResult.fromMap(_functionExceptionMap(e));
  } on TimeoutException {
    return const PaymongoReconcileResult(
      outcome: 'pending',
      error: 'Payment confirmation timed out.',
    );
  } catch (_) {
    return const PaymongoReconcileResult(
      outcome: 'pending',
      error: 'Unable to confirm payment status right now.',
    );
  }
}

Future<PaymongoReconcileResult> finalizeMyPaymongoCheckout(
  SupabaseService supabase, {
  required String orderId,
  required String clientOutcome,
  bool restoreCart = true,
}) async {
  try {
    final response = await supabase.client.rpc(
      'finalize_my_paymongo_checkout',
      params: {
        'p_order_id': orderId,
        'p_client_outcome': clientOutcome,
        'p_restore_cart': restoreCart,
      },
    );
    return PaymongoReconcileResult.fromFinalizeRpc(supabaseRpcMap(response));
  } catch (e) {
    debugPrint('finalize_my_paymongo_checkout error: $e');
    return const PaymongoReconcileResult(
      outcome: 'pending',
      error: 'Unable to finalize checkout.',
    );
  }
}

Future<PaymongoCheckoutResult> createPaymongoCheckout(
  SupabaseService supabase, {
  required String orderId,
  required String channel,
}) async {
  final parsed = parsePaymongoChannel(channel);
  if (parsed == null) {
    return const PaymongoCheckoutResult(
      success: false,
      error: 'Choose Card or GCash.',
    );
  }
  try {
    final prepRaw = await supabase.client.rpc(
      'prepare_paymongo_checkout',
      params: {'p_order_id': orderId, 'p_channel': parsed},
    );
    final prep = supabaseRpcMap(prepRaw);
    if (prep == null || prep['success'] != true) {
      final message = buyerFacingPaymentStartError(
        supabaseRpcError(
          prep,
          fallback: 'Unable to start payment right now. Please try again.',
        ),
      );
      debugPrint('prepare_paymongo_checkout failed: $prepRaw');
      return PaymongoCheckoutResult(success: false, error: message);
    }
    if (prep['already_paid'] == true) {
      return PaymongoCheckoutResult.fromMap(prep);
    }
    if (prep['reuse'] == true) {
      final reuseUrl = prep['checkout_url']?.toString().trim();
      if (reuseUrl != null &&
          reuseUrl.isNotEmpty &&
          isSafePaymongoCheckoutUrl(reuseUrl)) {
        return PaymongoCheckoutResult.fromMap({
          'success': true,
          'already_paid': false,
          'checkout_url': reuseUrl,
          'session_id': prep['session_id'],
        });
      }
    }

    final response = await supabase.client.functions.invoke(
      'create-paymongo-checkout',
      body: {'order_id': orderId, 'payment_method': parsed},
    );
    final map = supabaseRpcMap(response.data);
    if (map == null) {
      debugPrint(
        'create-paymongo-checkout empty body status=${response.status}',
      );
      return const PaymongoCheckoutResult(
        success: false,
        error: 'Unable to start payment right now. Please try again.',
      );
    }
    return PaymongoCheckoutResult.fromMap(map);
  } on PostgrestException catch (e) {
    debugPrint(
      'prepare_paymongo_checkout PostgrestException '
      'code=${e.code} message=${e.message}',
    );
    return PaymongoCheckoutResult(
      success: false,
      error: buyerFacingPaymentStartError(e.message),
    );
  } on FunctionException catch (e) {
    debugPrint(
      'create-paymongo-checkout FunctionException '
      'status=${e.status} details=${e.details}',
    );
    return PaymongoCheckoutResult.fromMap(_functionExceptionMap(e));
  } catch (e, st) {
    debugPrint('createPaymongoCheckout error: $e\n$st');
    return const PaymongoCheckoutResult(
      success: false,
      error: 'Unable to start payment right now. Please try again.',
    );
  }
}

Map<String, dynamic>? _functionExceptionMap(FunctionException error) {
  final payload = parseEdgeFunctionError(error.details);
  final message = payload.message?.trim();
  if (message != null && message.isNotEmpty) {
    return {'success': false, 'error': message};
  }
  final details = error.details;
  if (details is Map) return supabaseRpcMap(details);
  if (details is String && details.trim().isNotEmpty) {
    try {
      return supabaseRpcMap(jsonDecode(details));
    } catch (_) {}
  }
  return {
    'success': false,
    'error': 'Unable to start payment right now. Please try again.',
  };
}
