import '../../../core/utils/formatters.dart';

class DeliveryPaymentHold {
  const DeliveryPaymentHold({
    required this.escrowId,
    required this.orderId,
    required this.status,
    required this.amountCentavos,
    required this.sellerAmountCentavos,
    this.refundProvider = 'none',
    this.releaseReason,
    this.refundReason,
    this.buyerId,
    this.refundState,
    this.refundProviderStatus,
    this.refundProviderError,
    this.paymongoRefundId,
    this.refundLocked = false,
    this.refundLastCheckedAt,
    this.refundCompletedAt,
  });

  final String escrowId;
  final String orderId;
  final String status;
  final int amountCentavos;
  final int sellerAmountCentavos;
  final String refundProvider;
  final String? releaseReason;
  final String? refundReason;
  final String? buyerId;

  /// provider_pending | awaiting_buyer_claim | manual_required |
  /// succeeded | manual_completed. Null until a refund is decided.
  final String? refundState;
  final String? refundProviderStatus;
  final String? refundProviderError;
  final String? paymongoRefundId;

  /// A PayMongo call is in flight or its result is unconfirmed.
  final bool refundLocked;
  final DateTime? refundLastCheckedAt;
  final DateTime? refundCompletedAt;

  bool get canDecide => status == 'held' || status == 'disputed';

  bool get isReleased => status == 'released';

  bool get isRefunded => status == 'refunded';

  bool get refundIsComplete =>
      refundState == 'succeeded' || refundState == 'manual_completed';

  bool get refundNeedsManualAction =>
      isRefunded && refundState == 'manual_required';

  factory DeliveryPaymentHold.fromSupabase(Map<String, dynamic> row) {
    int asCentavos(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    DateTime? time(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

    return DeliveryPaymentHold(
      escrowId: row['escrow_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      status: row['status'] as String? ?? '',
      amountCentavos: asCentavos(row['amount_centavos']),
      sellerAmountCentavos: asCentavos(row['seller_amount_centavos']),
      refundProvider: row['refund_provider'] as String? ?? 'none',
      releaseReason: row['release_reason'] as String?,
      refundReason: row['refund_reason'] as String?,
      buyerId: row['buyer_id'] as String?,
      refundState: (row['refund_state'] as String?)?.trim(),
      refundProviderStatus: row['refund_provider_status'] as String?,
      refundProviderError: row['refund_provider_error'] as String?,
      paymongoRefundId: row['paymongo_refund_id'] as String?,
      refundLocked: row['refund_lock_at'] != null,
      refundLastCheckedAt: time(row['refund_last_checked_at']),
      refundCompletedAt: time(row['refund_completed_at']),
    );
  }
}

/// Admin-facing label for where a buyer refund stands.
String adminRefundStateLabel(String? state) => switch (state) {
  'provider_pending' => 'Refund pending (legacy)',
  'awaiting_buyer_claim' => 'Refund pending (legacy)',
  'manual_required' => 'Manual GCash refund needed',
  'succeeded' => 'Refund completed',
  'manual_completed' => 'Refunded by GCash',
  _ => 'Refund status unknown',
};

String adminRefundStateHint(DeliveryPaymentHold hold) {
  return switch (hold.refundState) {
    'provider_pending' =>
      'Legacy PayMongo refund still marked in progress. Check PayMongo status '
          'once, then send GCash manually if PayMongo did not pay the buyer.',
    'awaiting_buyer_claim' =>
      'Legacy PayMongo claim link may still exist. Prefer manual GCash and '
          'record the transfer here.',
    'manual_required' =>
      'Send the buyer a GCash transfer for the refund amount, then record the '
          'reference and receipt below. Do not mark complete until GCash is sent.',
    'succeeded' => 'The buyer received this refund (legacy PayMongo confirmation).',
    'manual_completed' =>
      'An admin recorded a GCash transfer to the buyer with a receipt.',
    _ => '',
  };
}

bool canResolveDeliveryPayment(String? status) =>
    status == 'held' || status == 'disputed';

String deliveryHoldStatusLabel(String status) => switch (status) {
  'held' => 'Payment held',
  'disputed' => 'Payment on hold',
  'released' => 'Released as earnings',
  'refunded' => 'Refunded to buyer',
  _ => 'Payment update',
};

String deliveryHoldHint(String status) => switch (status) {
  'held' => 'The buyer paid. This amount is not seller earnings yet.',
  'disputed' =>
    'A delivery problem is holding this payment. Dismiss the case or choose a payment outcome.',
  'released' => 'This amount is available as seller earnings.',
  'refunded' => 'This amount is not seller earnings.',
  _ => '',
};

String refundProviderMessage(String provider, {String? refundState}) {
  if (refundState != null) {
    return switch (refundState) {
      'succeeded' => 'PayMongo returned the payment to the buyer.',
      'manual_completed' => 'An admin sent the refund to the buyer by GCash.',
      'provider_pending' => 'PayMongo is still processing this refund.',
      'awaiting_buyer_claim' =>
        'PayMongo sent a claim link. Waiting for the buyer to claim it.',
      'manual_required' =>
        'Send the buyer a manual GCash refund, then record it in Buyer refunds.',
      _ => 'Refund decided. Status is not confirmed yet.',
    };
  }
  if (provider == 'paymongo') {
    return 'Refund sent through the original payment method.';
  }
  return 'Refund recorded. The payment provider did not process an automatic refund.';
}

String refundBuyerCtaLabel(int amountCentavos) =>
    'Refund ${formatCentavos(amountCentavos)} to buyer';

String releaseSellerCtaLabel(int amountCentavos) =>
    'Release ${formatCentavos(amountCentavos)} to seller';

bool isFinancialDeliveryDecision(String decision) {
  final value = decision.trim().toLowerCase();
  return value == 'refund' || value == 'release';
}

bool communityReportDecisionMovesMoney(String decision) {
  final value = decision.trim().toLowerCase();
  return isFinancialDeliveryDecision(value) &&
      value != 'action_taken' &&
      value != 'resolved' &&
      value != 'dismissed';
}
