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
  });

  final String escrowId;
  final String orderId;
  final String status;
  final int amountCentavos;
  final int sellerAmountCentavos;
  final String refundProvider;
  final String? releaseReason;
  final String? refundReason;

  bool get canDecide => status == 'held' || status == 'disputed';

  bool get isReleased => status == 'released';

  bool get isRefunded => status == 'refunded';

  factory DeliveryPaymentHold.fromSupabase(Map<String, dynamic> row) {
    int asCentavos(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DeliveryPaymentHold(
      escrowId: row['escrow_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      status: row['status'] as String? ?? '',
      amountCentavos: asCentavos(row['amount_centavos']),
      sellerAmountCentavos: asCentavos(row['seller_amount_centavos']),
      refundProvider: row['refund_provider'] as String? ?? 'none',
      releaseReason: row['release_reason'] as String?,
      refundReason: row['refund_reason'] as String?,
    );
  }
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

String refundProviderMessage(String provider) {
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
