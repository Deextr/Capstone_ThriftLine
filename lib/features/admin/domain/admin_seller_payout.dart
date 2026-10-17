import '../../seller/data/seller_earnings.dart'
    show SellerPayoutStatus, readCentavos, sellerPayoutStatusFromRaw;

export '../../seller/data/seller_earnings.dart' show SellerPayoutStatus;

enum AdminPayoutStatusFilter { requested, paid, rejected, cancelled, all }

extension AdminPayoutStatusFilterX on AdminPayoutStatusFilter {
  String get label => switch (this) {
    AdminPayoutStatusFilter.requested => 'Waiting for transfer',
    AdminPayoutStatusFilter.paid => 'Paid',
    AdminPayoutStatusFilter.rejected => 'Rejected',
    AdminPayoutStatusFilter.cancelled => 'Cancelled by seller',
    AdminPayoutStatusFilter.all => 'All payouts',
  };

  /// Value sent to `admin_list_seller_payouts`; null means every status.
  String? get rpcValue => switch (this) {
    AdminPayoutStatusFilter.all => null,
    _ => name,
  };
}

String adminPayoutStatusLabel(SellerPayoutStatus status) => switch (status) {
  SellerPayoutStatus.requested => 'Waiting for transfer',
  SellerPayoutStatus.paid => 'Paid',
  SellerPayoutStatus.rejected => 'Rejected',
  SellerPayoutStatus.cancelled => 'Cancelled',
};

/// Key understood by `AdminStatusBadge` colors.
String adminPayoutBadgeKey(SellerPayoutStatus status) => switch (status) {
  SellerPayoutStatus.requested => 'pending',
  SellerPayoutStatus.paid => 'paid',
  SellerPayoutStatus.rejected => 'rejected',
  SellerPayoutStatus.cancelled => 'closed',
};

class AdminSellerPayout {
  const AdminSellerPayout({
    required this.payoutId,
    required this.sellerId,
    required this.sellerName,
    required this.amountCentavos,
    required this.status,
    this.sellerEmail,
    this.shopName,
    this.requestedAt,
    this.gcashAccountName,
    this.gcashMobileNumber,
    this.gcashReference,
    this.transferredAmountCentavos,
    this.transferredAt,
    this.evidencePath,
    this.processedBy,
    this.processedAt,
    this.adminNote,
    this.rejectionReason,
    this.cancelledAt,
    this.sellerAvailableCentavos = 0,
  });

  final String payoutId;
  final String sellerId;
  final String sellerName;
  final String? sellerEmail;
  final String? shopName;
  final int amountCentavos;
  final SellerPayoutStatus status;
  final DateTime? requestedAt;
  final String? gcashAccountName;
  final String? gcashMobileNumber;
  final String? gcashReference;
  final int? transferredAmountCentavos;
  final DateTime? transferredAt;
  final String? evidencePath;
  final String? processedBy;
  final DateTime? processedAt;
  final String? adminNote;
  final String? rejectionReason;
  final DateTime? cancelledAt;

  /// Seller balance not yet requested or paid, at the time of loading.
  final int sellerAvailableCentavos;

  bool get isOpen => status == SellerPayoutStatus.requested;

  bool get hasGcashDestination =>
      (gcashAccountName ?? '').isNotEmpty &&
      (gcashMobileNumber ?? '').isNotEmpty;

  String get sellerDisplayName {
    final shop = shopName?.trim() ?? '';
    return shop.isNotEmpty ? shop : sellerName;
  }

  factory AdminSellerPayout.fromMap(Map<String, dynamic> map) {
    DateTime? time(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    String? text(dynamic v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    final transferred = map['transferred_amount_centavos'];
    return AdminSellerPayout(
      payoutId: map['payout_id']?.toString() ?? '',
      sellerId: map['seller_id']?.toString() ?? '',
      sellerName: text(map['seller_name']) ?? 'Seller',
      sellerEmail: text(map['seller_email']),
      shopName: text(map['shop_name']),
      amountCentavos: readCentavos(map['amount_centavos']),
      status: sellerPayoutStatusFromRaw(map['status']?.toString()),
      requestedAt: time(map['requested_at']),
      gcashAccountName: text(map['gcash_account_name']),
      gcashMobileNumber: text(map['gcash_mobile_number']),
      gcashReference: text(map['gcash_reference']),
      transferredAmountCentavos: transferred == null
          ? null
          : readCentavos(transferred),
      transferredAt: time(map['transferred_at']),
      evidencePath: text(map['evidence_path']),
      processedBy: text(map['processed_by']),
      processedAt: time(map['processed_at']),
      adminNote: text(map['admin_note']),
      rejectionReason: text(map['rejection_reason']),
      cancelledAt: time(map['cancelled_at']),
      sellerAvailableCentavos: readCentavos(map['seller_available_centavos']),
    );
  }
}

class AdminSellerPayoutCounts {
  const AdminSellerPayoutCounts({
    this.requested = 0,
    this.paid = 0,
    this.rejected = 0,
    this.cancelled = 0,
  });

  final int requested;
  final int paid;
  final int rejected;
  final int cancelled;

  int get all => requested + paid + rejected + cancelled;

  int forFilter(AdminPayoutStatusFilter filter) => switch (filter) {
    AdminPayoutStatusFilter.requested => requested,
    AdminPayoutStatusFilter.paid => paid,
    AdminPayoutStatusFilter.rejected => rejected,
    AdminPayoutStatusFilter.cancelled => cancelled,
    AdminPayoutStatusFilter.all => all,
  };

  factory AdminSellerPayoutCounts.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AdminSellerPayoutCounts();
    return AdminSellerPayoutCounts(
      requested: readCentavos(map['requested']),
      paid: readCentavos(map['paid']),
      rejected: readCentavos(map['rejected']),
      cancelled: readCentavos(map['cancelled']),
    );
  }
}

class AdminSellerPayoutPage {
  const AdminSellerPayoutPage({
    required this.items,
    required this.total,
    required this.counts,
  });

  final List<AdminSellerPayout> items;
  final int total;
  final AdminSellerPayoutCounts counts;
}

/// Parses a peso amount typed by an admin (e.g. `1,250.50`) into centavos.
int? parsePesoToCentavos(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[₱,\s]'), '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final pesos = int.parse(parts[0]);
  final cents = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return pesos * 100 + cents;
}

String? validateTransferReference(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Enter the GCash reference number.';
  if (value.length < 4 || value.length > 64) {
    return 'Reference must be 4 to 64 characters.';
  }
  return null;
}

String? validateTransferAmount(String raw, int expectedCentavos) {
  final centavos = parsePesoToCentavos(raw);
  if (centavos == null) return 'Enter the amount you sent, like 1250.00.';
  if (centavos != expectedCentavos) {
    return 'The amount sent must match the requested amount exactly.';
  }
  return null;
}

String? validateTransferDate(DateTime? sentAt, {DateTime? now}) {
  if (sentAt == null) return 'Choose the date you sent the transfer.';
  final current = now ?? DateTime.now();
  if (sentAt.isAfter(current.add(const Duration(hours: 1)))) {
    return 'The transfer date cannot be in the future.';
  }
  return null;
}

String? validateRejectionReason(String raw) {
  final value = raw.trim();
  if (value.length < 5) return 'Tell the seller why, in a short sentence.';
  if (value.length > 500) return 'Keep the reason under 500 characters.';
  return null;
}
