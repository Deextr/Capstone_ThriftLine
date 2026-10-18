import '../../../core/utils/formatters.dart';
import '../../../core/utils/transaction_history_format.dart';
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
    this.productImageUrl,
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
    this.subtotalCentavos = 0,
    this.shippingFeeCentavos = 0,
    this.commissionRate = 0.05,
    this.commissionAmountCentavos = 0,
    this.commissionStatus = 'pending',
    this.orderStatus,
  });

  final String paymentId;
  final String orderId;
  final String orderNumber;
  final String productTitle;
  final String? productImageUrl;
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
  final int subtotalCentavos;
  final int shippingFeeCentavos;
  final double commissionRate;
  final int commissionAmountCentavos;
  final String commissionStatus;
  final String? orderStatus;

  int get netProductEarningsCentavos {
    final net = subtotalCentavos - commissionAmountCentavos;
    return net < 0 ? 0 : net;
  }

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
      productImageUrl: sanitizeTransactionProductImageUrl(
        json['product_image_url'] as String?,
      ),
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
      subtotalCentavos: (json['subtotal_centavos'] as num?)?.toInt() ?? 0,
      shippingFeeCentavos:
          (json['shipping_fee_centavos'] as num?)?.toInt() ?? 0,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0.05,
      commissionAmountCentavos:
          (json['commission_amount_centavos'] as num?)?.toInt() ?? 0,
      commissionStatus:
          (json['commission_status'] as String?)?.trim().isNotEmpty == true
          ? (json['commission_status'] as String).trim()
          : 'pending',
      orderStatus: (json['order_status'] as String?)?.trim(),
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

String sellerCommissionStatusLabel(String? status) {
  return switch ((status ?? '').trim().toLowerCase()) {
    'earned' => 'Earned',
    'reversed' => 'Waived after refund',
    'void' => 'Not earned',
    'pending' => 'Not yet earned',
    _ => 'Not yet earned',
  };
}

extension SellerTransactionFilterLabel on BuyerTransactionFilter {
  String get sellerHistoryLabel => switch (this) {
    BuyerTransactionFilter.all => 'All',
    BuyerTransactionFilter.successful => 'Sales',
    BuyerTransactionFilter.refunded => 'Refunds',
  };
}

/// Seller-facing payment status (plain language, not buyer-centric).
String sellerTransactionStatusLabel(BuyerTransactionStatus status) {
  return switch (status) {
    BuyerTransactionStatus.successful => 'Completed',
    BuyerTransactionStatus.refundInProgress => 'Buyer refund in progress',
    BuyerTransactionStatus.refunded => 'Buyer refunded',
  };
}

/// Short list-row hint when a buyer refund affects seller earnings.
String? sellerRefundEarningsListHint(SellerTransaction transaction) {
  final amount = transaction.refundAmountCentavos;
  if (amount == null || amount <= 0) return null;
  if (transaction.status == BuyerTransactionStatus.successful) return null;
  final formatted = formatCentavos(amount);
  return switch (transaction.status) {
    BuyerTransactionStatus.refunded =>
      '−$formatted deducted — returned to buyer',
    BuyerTransactionStatus.refundInProgress =>
      'Up to $formatted may be deducted if refund completes',
    BuyerTransactionStatus.successful => null,
  };
}

String sellerTransactionTypeSubtitle(SellerTransaction transaction) {
  final method = transaction.methodLabel;
  return switch (transaction.status) {
    BuyerTransactionStatus.successful => 'Sale · $method',
    BuyerTransactionStatus.refundInProgress => 'Refund · $method',
    BuyerTransactionStatus.refunded => 'Refund · $method',
  };
}

String sellerRefundDetailExplanation(SellerTransaction transaction) {
  return switch (transaction.status) {
    BuyerTransactionStatus.refunded =>
      'The buyer was refunded. This amount was deducted from your earnings '
          'for this order.',
    BuyerTransactionStatus.refundInProgress =>
      'The buyer\'s refund is still in progress. Your earnings may be '
          'adjusted when it is completed.',
    BuyerTransactionStatus.successful => '',
  };
}
