enum BuyerTransactionStatus { successful, refunded }

enum BuyerTransactionFilter { all, successful, refunded }

enum BuyerTransactionSort { newest, oldest }

extension BuyerTransactionFilterLabel on BuyerTransactionFilter {
  String get label => switch (this) {
    BuyerTransactionFilter.all => 'All',
    BuyerTransactionFilter.successful => 'Successful payments',
    BuyerTransactionFilter.refunded => 'Refunded payments',
  };
}

extension BuyerTransactionSortLabel on BuyerTransactionSort {
  String get menuLabel => switch (this) {
    BuyerTransactionSort.newest => 'Newest to oldest',
    BuyerTransactionSort.oldest => 'Oldest to newest',
  };
}

List<BuyerTransaction> visibleBuyerTransactions({
  required List<BuyerTransaction> source,
  required BuyerTransactionFilter filter,
  required BuyerTransactionSort sort,
}) {
  Iterable<BuyerTransaction> rows = source;
  rows = switch (filter) {
    BuyerTransactionFilter.all => rows,
    BuyerTransactionFilter.successful => rows.where(
      (t) => t.status == BuyerTransactionStatus.successful,
    ),
    BuyerTransactionFilter.refunded => rows.where(
      (t) => t.status == BuyerTransactionStatus.refunded,
    ),
  };
  final list = rows.toList();
  list.sort((a, b) {
    final cmp = a.sortDate.compareTo(b.sortDate);
    return sort == BuyerTransactionSort.newest ? -cmp : cmp;
  });
  return list;
}

BuyerTransactionStatus? buyerTransactionStatusFromPayment(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'paid':
      return BuyerTransactionStatus.successful;
    case 'refunded':
      return BuyerTransactionStatus.refunded;
    default:
      return null;
  }
}

String buyerTransactionStatusLabel(BuyerTransactionStatus status) {
  return switch (status) {
    BuyerTransactionStatus.successful => 'Successful',
    BuyerTransactionStatus.refunded => 'Refunded',
  };
}

String buyerPaymentMethodLabel({
  required String? paymentMethod,
  required String? paymongoChannel,
}) {
  final channel = (paymongoChannel ?? '').trim().toLowerCase();
  if (channel == 'gcash') return 'GCash';
  if (channel == 'card') return 'Card';
  switch ((paymentMethod ?? '').trim().toLowerCase()) {
    case 'gcash':
      return 'GCash';
    case 'paymongo':
      return 'PayMongo';
    case 'cod':
      return 'Cash on delivery';
    case 'bank_transfer':
      return 'Bank transfer';
    default:
      return 'Payment';
  }
}

class BuyerTransaction {
  const BuyerTransaction({
    required this.paymentId,
    required this.orderId,
    required this.orderNumber,
    required this.productTitle,
    required this.status,
    required this.amountCentavos,
    this.paidAt,
    this.paymentMethod,
    this.paymongoChannel,
    this.transactionReference,
    this.refundedAt,
    this.refundAmountCentavos,
    this.refundProviderStatus,
  });

  final String paymentId;
  final String orderId;
  final String orderNumber;
  final String productTitle;
  final BuyerTransactionStatus status;
  final int amountCentavos;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String? paymongoChannel;
  final String? transactionReference;
  final DateTime? refundedAt;
  final int? refundAmountCentavos;
  final String? refundProviderStatus;

  DateTime get sortDate =>
      refundedAt ?? paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  String get methodLabel => buyerPaymentMethodLabel(
    paymentMethod: paymentMethod,
    paymongoChannel: paymongoChannel,
  );

  factory BuyerTransaction.fromJson(Map<String, dynamic> json) {
    final status = buyerTransactionStatusFromPayment(
      json['payment_status'] as String?,
    );
    if (status == null) {
      throw FormatException('Unsupported payment status');
    }
    return BuyerTransaction(
      paymentId: json['payment_id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      orderNumber: (json['order_number'] as String?)?.trim() ?? '',
      productTitle:
          (json['product_title'] as String?)?.trim().isNotEmpty == true
          ? (json['product_title'] as String).trim()
          : 'Order',
      status: status,
      amountCentavos: (json['amount_centavos'] as num?)?.toInt() ?? 0,
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
      paymentMethod: json['payment_method'] as String?,
      paymongoChannel: json['paymongo_channel'] as String?,
      transactionReference: (json['transaction_reference'] as String?)?.trim(),
      refundedAt: DateTime.tryParse(json['refunded_at'] as String? ?? ''),
      refundAmountCentavos: (json['refund_amount_centavos'] as num?)?.toInt(),
      refundProviderStatus: json['refund_provider_status'] as String?,
    );
  }
}
