import '../../../core/utils/formatters.dart';
import '../../../core/utils/transaction_history_format.dart';

enum BuyerTransactionStatus { successful, refundInProgress, refunded }

enum BuyerTransactionFilter { all, successful, refunded }

enum BuyerTransactionSort { newest, oldest }

/// Server-owned refund progress for a refunded escrow.
enum BuyerRefundState {
  providerPending,
  awaitingBuyerClaim,
  manualRequired,
  succeeded,
  manualCompleted,
}

BuyerRefundState? buyerRefundStateFromRaw(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'provider_pending' => BuyerRefundState.providerPending,
    'awaiting_buyer_claim' => BuyerRefundState.awaitingBuyerClaim,
    'manual_required' => BuyerRefundState.manualRequired,
    'succeeded' => BuyerRefundState.succeeded,
    'manual_completed' => BuyerRefundState.manualCompleted,
    _ => null,
  };
}

bool buyerRefundStateIsComplete(BuyerRefundState? state) =>
    state == BuyerRefundState.succeeded ||
    state == BuyerRefundState.manualCompleted;

extension BuyerTransactionFilterLabel on BuyerTransactionFilter {
  String get label => switch (this) {
    BuyerTransactionFilter.all => 'All',
    BuyerTransactionFilter.successful => 'Successful payments',
    BuyerTransactionFilter.refunded => 'Refunds',
  };

  /// Shorter chip labels on the buyer transaction history screen.
  String get buyerHistoryLabel => switch (this) {
    BuyerTransactionFilter.all => 'All',
    BuyerTransactionFilter.successful => 'Paid',
    BuyerTransactionFilter.refunded => 'Refunds',
  };
}

extension BuyerTransactionSortLabel on BuyerTransactionSort {
  String get menuLabel => switch (this) {
    BuyerTransactionSort.newest => 'Newest to oldest',
    BuyerTransactionSort.oldest => 'Oldest to newest',
  };
}

DateTime _localCalendarDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Inclusive local-date range filter (start/end normalized to calendar days).
bool buyerTransactionMatchesDateRange(
  BuyerTransaction t, {
  DateTime? from,
  DateTime? to,
}) {
  if (from == null && to == null) return true;
  final eventDay = _localCalendarDay(t.sortDate);
  if (from != null) {
    final start = _localCalendarDay(from);
    if (eventDay.isBefore(start)) return false;
  }
  if (to != null) {
    final end = _localCalendarDay(to);
    if (eventDay.isAfter(end)) return false;
  }
  return true;
}

String buyerTransactionDateFilterSummary({
  required DateTime? from,
  required DateTime? to,
}) {
  if (from == null && to == null) return '';
  final start = from != null ? _localCalendarDay(from) : null;
  final end = to != null ? _localCalendarDay(to) : null;
  if (start != null && end != null && start == end) {
    return formatFullDate(start);
  }
  if (start != null && end != null) {
    return '${formatFullDate(start)} – ${formatFullDate(end)}';
  }
  if (start != null) return 'From ${formatFullDate(start)}';
  return 'Until ${formatFullDate(end!)}';
}

bool buyerTransactionMatchesFilter(
  BuyerTransaction t,
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

List<BuyerTransaction> visibleBuyerTransactions({
  required List<BuyerTransaction> source,
  required BuyerTransactionFilter filter,
  required BuyerTransactionSort sort,
  DateTime? dateFrom,
  DateTime? dateTo,
}) {
  final list = source
      .where((t) => buyerTransactionMatchesFilter(t, filter))
      .where(
        (t) => buyerTransactionMatchesDateRange(
          t,
          from: dateFrom,
          to: dateTo,
        ),
      )
      .toList();
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

/// A payment stays `paid` until the money is confirmed back with the buyer.
BuyerTransactionStatus? buyerTransactionStatusFrom({
  required String? paymentStatus,
  required BuyerRefundState? refundState,
}) {
  final base = buyerTransactionStatusFromPayment(paymentStatus);
  if (base == null) return null;
  if (base == BuyerTransactionStatus.refunded) return base;
  if (refundState == null) return base;
  return buyerRefundStateIsComplete(refundState)
      ? BuyerTransactionStatus.refunded
      : BuyerTransactionStatus.refundInProgress;
}

String buyerTransactionStatusLabel(BuyerTransactionStatus status) {
  return switch (status) {
    BuyerTransactionStatus.successful => 'Successful',
    BuyerTransactionStatus.refundInProgress => 'Refund in progress',
    BuyerTransactionStatus.refunded => 'Refunded',
  };
}

String buyerTransactionTypeSubtitle(BuyerTransaction transaction) {
  final method = transaction.methodLabel;
  return switch (transaction.status) {
    BuyerTransactionStatus.successful => 'Payment · $method',
    BuyerTransactionStatus.refundInProgress => 'Refund · $method',
    BuyerTransactionStatus.refunded => 'Refund · $method',
  };
}

/// Short headline for the refund step the buyer is on.
String buyerRefundHeadline(BuyerRefundState state, {bool gcashSent = false}) {
  return switch (state) {
    BuyerRefundState.providerPending => 'Refund pending',
    BuyerRefundState.awaitingBuyerClaim => 'Refund pending',
    BuyerRefundState.manualRequired =>
      gcashSent ? 'Refund pending' : 'Refund pending',
    BuyerRefundState.succeeded => 'Refund completed',
    BuyerRefundState.manualCompleted => 'Refund completed',
  };
}

String buyerRefundExplanation(
  BuyerRefundState state, {
  bool gcashSent = false,
}) {
  return switch (state) {
    BuyerRefundState.providerPending =>
      'Your refund was approved and is still being processed. We will update '
          'this page when it is done.',
    BuyerRefundState.awaitingBuyerClaim =>
      'Your refund is still in progress. If you have an older PayMongo claim '
          'link, you may ignore it. Our team sends refunds through GCash.',
    BuyerRefundState.manualRequired =>
      gcashSent
          ? 'Our team will send your refund to the GCash number you provided. '
                'The GCash reference will appear here after it is sent.'
          : 'Add the GCash account where we should send your refund. Our team '
                'sends refunds manually through GCash; this is not automatic.',
    BuyerRefundState.succeeded =>
      'Your refund was confirmed.',
    BuyerRefundState.manualCompleted =>
      'Our team sent this refund to your GCash.',
  };
}

String buyerPaymentMethodLabel({
  required String? paymentMethod,
  required String? paymongoChannel,
}) {
  final channel = (paymongoChannel ?? '').trim().toLowerCase();
  if (channel == 'qrph') return 'QR Ph';
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

/// Only PayMongo-issued HTTPS links are shown to the buyer.
String? safeRefundClaimLink(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  return uri.toString();
}

class BuyerTransaction {
  const BuyerTransaction({
    required this.paymentId,
    required this.orderId,
    required this.orderNumber,
    required this.productTitle,
    this.productImageUrl,
    required this.status,
    required this.amountCentavos,
    this.paidAt,
    this.paymentMethod,
    this.paymongoChannel,
    this.transactionReference,
    this.refundedAt,
    this.refundAmountCentavos,
    this.refundProviderStatus,
    this.escrowId,
    this.refundState,
    this.refundCompletedAt,
    this.refundClaimLink,
    this.refundClaimLinkExpiresAt,
    this.refundGcashSubmitted = false,
    this.manualRefundReference,
  });

  final String paymentId;
  final String orderId;
  final String orderNumber;
  final String productTitle;
  final String? productImageUrl;
  final BuyerTransactionStatus status;
  final int amountCentavos;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String? paymongoChannel;
  final String? transactionReference;

  /// When the refund decision was made (order cancelled), not when money returned.
  final DateTime? refundedAt;
  final int? refundAmountCentavos;
  final String? refundProviderStatus;
  final String? escrowId;
  final BuyerRefundState? refundState;
  final DateTime? refundCompletedAt;
  final String? refundClaimLink;
  final DateTime? refundClaimLinkExpiresAt;
  final bool refundGcashSubmitted;
  final String? manualRefundReference;

  bool get hasRefund => refundState != null;

  bool get needsGcashDetails =>
      refundState == BuyerRefundState.manualRequired && !refundGcashSubmitted;

  bool get claimLinkExpired {
    final expires = refundClaimLinkExpiresAt;
    return expires != null && expires.isBefore(DateTime.now());
  }

  DateTime get sortDate =>
      refundedAt ?? paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  String get methodLabel => buyerPaymentMethodLabel(
    paymentMethod: paymentMethod,
    paymongoChannel: paymongoChannel,
  );

  factory BuyerTransaction.fromJson(Map<String, dynamic> json) {
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
    final reference = (json['manual_refund_reference'] as String?)?.trim();
    return BuyerTransaction(
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
      amountCentavos: (json['amount_centavos'] as num?)?.toInt() ?? 0,
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
      paymentMethod: json['payment_method'] as String?,
      paymongoChannel: json['paymongo_channel'] as String?,
      transactionReference: (json['transaction_reference'] as String?)?.trim(),
      refundedAt: DateTime.tryParse(json['refunded_at'] as String? ?? ''),
      refundAmountCentavos: (json['refund_amount_centavos'] as num?)?.toInt(),
      refundProviderStatus: json['refund_provider_status'] as String?,
      escrowId: json['escrow_id'] as String?,
      refundState: refundState,
      refundCompletedAt: DateTime.tryParse(
        json['refund_completed_at'] as String? ?? '',
      ),
      refundClaimLink: refundState == BuyerRefundState.awaitingBuyerClaim
          ? safeRefundClaimLink(json['refund_transfer_link'] as String?)
          : null,
      refundClaimLinkExpiresAt: DateTime.tryParse(
        json['refund_transfer_link_expires_at'] as String? ?? '',
      ),
      refundGcashSubmitted: json['refund_gcash_submitted'] == true,
      manualRefundReference: reference != null && reference.isNotEmpty
          ? reference
          : null,
    );
  }
}

/// Normalizes a PH mobile number to `09XXXXXXXXX`, or returns null if invalid.
String? normalizePhMobileNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+63')) digits = '0${digits.substring(3)}';
  if (digits.startsWith('63') && digits.length == 12) {
    digits = '0${digits.substring(2)}';
  }
  return RegExp(r'^09\d{9}$').hasMatch(digits) ? digits : null;
}

String? validateGcashAccountName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Enter the name on the GCash account.';
  if (name.length < 2) return 'Enter the full name on the GCash account.';
  if (name.length > 80) return 'Use 80 characters or fewer.';
  return null;
}

String? validateGcashMobileNumber(String raw) {
  if (raw.trim().isEmpty) return 'Enter the GCash mobile number.';
  if (normalizePhMobileNumber(raw) == null) {
    return 'Use an 11-digit number that starts with 09.';
  }
  return null;
}
