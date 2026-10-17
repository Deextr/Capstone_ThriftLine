import '../../../core/utils/fulfillment_sla.dart';

/// Mirrors [order_buyer_refund_completed] / admin_list_buyer_refunds "completed".
bool adminOrderRefundFinanciallyCompleted({
  required String paymentStatus,
  String? escrowStatus,
  String? refundState,
}) {
  final ps = paymentStatus.trim().toLowerCase();
  if (ps == 'refunded') return true;
  final escrow = escrowStatus?.trim().toLowerCase();
  final refund = refundState?.trim().toLowerCase();
  return escrow == 'refunded' &&
      (refund == 'succeeded' || refund == 'manual_completed');
}

/// Mirrors [order_buyer_refund_needs_action] / buyer refunds "needs_action".
bool adminOrderRefundNeedsAdminAction({
  String? escrowStatus,
  String? refundState,
}) {
  final escrow = escrowStatus?.trim().toLowerCase();
  final refund = refundState?.trim().toLowerCase();
  return escrow == 'refunded' && refund == 'manual_required';
}

/// Mirrors [order_fulfillment_overdue] when [stuckPreparing] matches DB stuck rule.
bool adminOrderFulfillmentOverdue({
  required bool stuckPreparing,
  required DateTime? paidAt,
  DateTime? now,
}) {
  if (!stuckPreparing || paidAt == null) return false;
  final clock = now ?? DateTime.now();
  return !clock.isBefore(paidAt.add(kFulfillmentAdminDelayed));
}

bool adminOrderFulfillmentOverdueFromSlaFlags(Map<String, dynamic>? flags) {
  if (flags == null) return false;
  return flags['fulfillment_overdue'] == true;
}

bool adminOrderRefundCompletedFromSlaFlags(Map<String, dynamic>? flags) {
  if (flags == null) return false;
  return flags['refund_completed'] == true;
}

bool adminOrderRefundNeedsActionFromSlaFlags(Map<String, dynamic>? flags) {
  if (flags == null) return false;
  return flags['refund_needs_action'] == true;
}

Map<String, dynamic>? adminOrderSlaFlagsFromRow(Map<String, dynamic> json) {
  final raw = json['admin_order_sla_flags'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    return Map<String, dynamic>.from(raw.first as Map);
  }
  return null;
}
