import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

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
    final outcome = (map['outcome'] ?? '').toString().trim().toLowerCase();
    final allowed = {'paid', 'pending', 'expired', 'failed', 'cancelled'};
    return PaymongoReconcileResult(
      outcome: allowed.contains(outcome) ? outcome : 'pending',
      error: map['error']?.toString(),
    );
  }
}

Future<PaymongoReconcileResult> reconcilePaymongoCheckout(
  SupabaseService supabase, {
  required String orderId,
}) async {
  try {
    final response = await supabase.client.functions.invoke(
      'reconcile-paymongo-checkout',
      body: {'order_id': orderId},
    );
    return PaymongoReconcileResult.fromMap(supabaseRpcMap(response.data));
  } on FunctionException catch (e) {
    return PaymongoReconcileResult.fromMap(_functionExceptionMap(e));
  } catch (_) {
    return const PaymongoReconcileResult(
      outcome: 'pending',
      error: 'Unable to confirm payment status right now.',
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
    final response = await supabase.client.functions.invoke(
      'create-paymongo-checkout',
      body: {'order_id': orderId, 'payment_method': parsed},
    );
    final map = supabaseRpcMap(response.data);
    if (map == null) {
      return const PaymongoCheckoutResult(
        success: false,
        error: 'Unable to start payment right now. Please try again.',
      );
    }
    return PaymongoCheckoutResult.fromMap(map);
  } on FunctionException catch (e) {
    return PaymongoCheckoutResult.fromMap(_functionExceptionMap(e));
  } catch (_) {
    return const PaymongoCheckoutResult(
      success: false,
      error: 'Unable to start payment right now. Please try again.',
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
  return {
    'success': false,
    'error': 'Unable to start payment right now. Please try again.',
  };
}
