import '../../buyer/data/buyer_transaction.dart';

export '../../buyer/data/buyer_transaction.dart'
    show
        BuyerRefundState,
        BuyerTransactionFilter,
        BuyerTransactionSort,
        BuyerTransactionStatus,
        buyerRefundHeadline,
        buyerTransactionStatusFrom,
        buyerTransactionStatusLabel,
        buyerPaymentMethodLabel;

/// A paid or refunded order on the seller side of the marketplace.
class SellerTransaction {
  const SellerTransaction({
    required this.paymentId,
    required this.orderId,
    required this.orderNumber,
    required this.productTitle,
    required this.status,
    required this.sellerAmountCentavos,
    required this.buyerPaidCentavos,
    this.paidAt,
    this.paymentMethod,
    this.paymongoChannel,
    this.transactionReference,
    this.refundedAt,
    this.refundAmountCentavos,
    this.refundProviderStatus,
    this.escrowId,
    this.escrowStatus,
    this.refundState,
    this.refundCompletedAt,
  });

  final String paymentId;
  final String orderId;
  final String orderNumber;
  final String productTitle;
  final BuyerTransactionStatus status;
  final int sellerAmountCentavos;
  final int buyerPaidCentavos;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String? paymongoChannel;
  final String? transactionReference;
  final DateTime? refundedAt;
  final int? refundAmountCentavos;
  final String? refundProviderStatus;
  final String? escrowId;
  final String? escrowStatus;
  final BuyerRefundState? refundState;
  final DateTime? refundCompletedAt;

  DateTime get sortDate =>
      refundedAt ?? paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  String get methodLabel => buyerPaymentMethodLabel(
    paymentMethod: paymentMethod,
    paymongoChannel: paymongoChannel,
  );

  factory SellerTransaction.fromJson(Map<String, dynamic> json) {
    final refundState = buyerRefundStateFromRaw(
      json['refund_state'] as String?,
    );
    final status = buyerTransactionStatusFrom(
      paymentStatus: json['payment_status'] as String?,
      refundState: refundState,
    );
    if (status == null) {
      throw FormatException('Unsupported payment status');
    }
    return SellerTransaction(
      paymentId: json['payment_id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      orderNumber: (json['order_number'] as String?)?.trim() ?? '',
      productTitle:
          (json['product_title'] as String?)?.trim().isNotEmpty == true
          ? (json['product_title'] as String).trim()
          : 'Order',
      status: status,
      sellerAmountCentavos:
          (json['seller_amount_centavos'] as num?)?.toInt() ?? 0,
      buyerPaidCentavos: (json['amount_centavos'] as num?)?.toInt() ?? 0,
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
      paymentMethod: json['payment_method'] as String?,
      paymongoChannel: json['paymongo_channel'] as String?,
      transactionReference: (json['transaction_reference'] as String?)?.trim(),
      refundedAt: DateTime.tryParse(json['refunded_at'] as String? ?? ''),
      refundAmountCentavos: (json['refund_amount_centavos'] as num?)?.toInt(),
      refundProviderStatus: json['refund_provider_status'] as String?,
      escrowId: json['escrow_id'] as String?,
      escrowStatus: json['escrow_status'] as String?,
      refundState: refundState,
      refundCompletedAt: DateTime.tryParse(
        json['refund_completed_at'] as String? ?? '',
      ),
    );
  }
}

bool sellerTransactionMatchesFilter(
  SellerTransaction t,
  BuyerTransactionFilter filter,
) {
  return switch (filter) {
    BuyerTransactionFilter.all => true,
    BuyerTransactionFilter.successful =>
      t.status == BuyerTransactionStatus.successful,
    BuyerTransactionFilter.refunded =>
      t.status == BuyerTransactionStatus.refunded ||
          t.status == BuyerTransactionStatus.refundInProgress,
  };
}

List<SellerTransaction> visibleSellerTransactions({
  required List<SellerTransaction> source,
  required BuyerTransactionFilter filter,
  required BuyerTransactionSort sort,
}) {
  final list = source
      .where((t) => sellerTransactionMatchesFilter(t, filter))
      .toList();
  list.sort((a, b) {
    final cmp = a.sortDate.compareTo(b.sortDate);
    return sort == BuyerTransactionSort.newest ? -cmp : cmp;
  });
  return list;
}

int sellerTransactionCountForFilter(
  List<SellerTransaction> source,
  BuyerTransactionFilter filter,
) {
  return source.where((t) => sellerTransactionMatchesFilter(t, filter)).length;
}

String sellerTransactionEarningsLabel(String? escrowStatus) {
  return switch ((escrowStatus ?? '').trim().toLowerCase()) {
    'held' => 'Earnings pending',
    'disputed' => 'On hold',
    'released' => 'Paid out to balance',
    'refunded' => 'Returned to buyer',
    _ => '',
  };
}
