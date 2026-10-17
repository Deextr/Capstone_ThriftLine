enum AdminBuyerRefundStatusFilter { needsAction, inProgress, completed, all }

extension AdminBuyerRefundStatusFilterX on AdminBuyerRefundStatusFilter {
  String get label => switch (this) {
    AdminBuyerRefundStatusFilter.needsAction => 'Needs admin action',
    AdminBuyerRefundStatusFilter.inProgress => 'In progress',
    AdminBuyerRefundStatusFilter.completed => 'Completed',
    AdminBuyerRefundStatusFilter.all => 'All refunds',
  };

  String? get rpcValue => switch (this) {
    AdminBuyerRefundStatusFilter.all => null,
    AdminBuyerRefundStatusFilter.needsAction => 'needs_action',
    AdminBuyerRefundStatusFilter.inProgress => 'in_progress',
    AdminBuyerRefundStatusFilter.completed => 'completed',
  };
}

String adminBuyerRefundBadgeKey(String? refundState) => switch (refundState) {
  'manual_required' => 'pending',
  'provider_pending' => 'processing',
  'awaiting_buyer_claim' => 'awaiting_review',
  'succeeded' => 'paid',
  'manual_completed' => 'paid',
  _ => 'processing',
};

class AdminBuyerRefundRow {
  const AdminBuyerRefundRow({
    required this.escrowId,
    required this.orderId,
    required this.orderNumber,
    required this.buyerId,
    required this.buyerName,
    required this.amountCentavos,
    required this.refundState,
    this.buyerEmail,
    this.refundProviderStatus,
    this.refundLocked = false,
    this.refundedAt,
    this.paymongoRefundId,
    this.buyerGcashSubmitted = false,
    this.gcashAccountName,
    this.gcashMobileNumber,
    this.hasClaimLink = false,
  });

  final String escrowId;
  final String orderId;
  final String orderNumber;
  final String buyerId;
  final String buyerName;
  final String? buyerEmail;
  final int amountCentavos;
  final String refundState;
  final String? refundProviderStatus;
  final bool refundLocked;
  final DateTime? refundedAt;
  final String? paymongoRefundId;
  final bool buyerGcashSubmitted;
  final String? gcashAccountName;
  final String? gcashMobileNumber;
  final bool hasClaimLink;

  factory AdminBuyerRefundRow.fromMap(Map<String, dynamic> map) {
    DateTime? time(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    String? text(dynamic v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return AdminBuyerRefundRow(
      escrowId: text(map['escrow_id']) ?? '',
      orderId: text(map['order_id']) ?? '',
      orderNumber: text(map['order_number']) ?? '',
      buyerId: text(map['buyer_id']) ?? '',
      buyerName: text(map['buyer_name']) ?? 'Buyer',
      buyerEmail: text(map['buyer_email']),
      amountCentavos: (map['amount_centavos'] as num?)?.toInt() ?? 0,
      refundState: text(map['refund_state']) ?? '',
      refundProviderStatus: text(map['refund_provider_status']),
      refundLocked: map['refund_locked'] == true,
      refundedAt: time(map['refunded_at']),
      paymongoRefundId: text(map['paymongo_refund_id']),
      buyerGcashSubmitted: map['buyer_gcash_submitted'] == true,
      gcashAccountName: text(map['gcash_account_name']),
      gcashMobileNumber: text(map['gcash_mobile_number']),
      hasClaimLink: map['has_claim_link'] == true,
    );
  }
}

class AdminBuyerRefundCounts {
  const AdminBuyerRefundCounts({
    this.needsAction = 0,
    this.inProgress = 0,
    this.completed = 0,
  });

  final int needsAction;
  final int inProgress;
  final int completed;

  factory AdminBuyerRefundCounts.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AdminBuyerRefundCounts();
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    return AdminBuyerRefundCounts(
      needsAction: count('needs_action'),
      inProgress: count('in_progress'),
      completed: count('completed'),
    );
  }

  int forFilter(AdminBuyerRefundStatusFilter filter) => switch (filter) {
    AdminBuyerRefundStatusFilter.needsAction => needsAction,
    AdminBuyerRefundStatusFilter.inProgress => inProgress,
    AdminBuyerRefundStatusFilter.completed => completed,
    AdminBuyerRefundStatusFilter.all => needsAction + inProgress + completed,
  };
}

/// True when admins should use the Buyer Refunds module for this escrow refund.
bool adminBuyerRefundNeedsAdminAction({String? refundState}) =>
    refundState?.trim().toLowerCase() == 'manual_required';

class AdminBuyerRefundPage {
  const AdminBuyerRefundPage({
    required this.items,
    required this.total,
    required this.counts,
  });

  final List<AdminBuyerRefundRow> items;
  final int total;
  final AdminBuyerRefundCounts counts;
}
