import 'package:flutter/foundation.dart';

/// Released earnings minus payouts still waiting and payouts already sent.
@visibleForTesting
int sellerAvailableCentavos({
  required int releasedCentavos,
  required int payoutRequestedCentavos,
  int payoutPaidCentavos = 0,
}) {
  final available =
      releasedCentavos - payoutRequestedCentavos - payoutPaidCentavos;
  return available < 0 ? 0 : available;
}

@visibleForTesting
bool sellerPayoutAmountAllowed(int requestedCentavos, int availableCentavos) {
  return requestedCentavos >= 100 && requestedCentavos <= availableCentavos;
}

int readCentavos(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String sellerEscrowStatusLabel(String status) => switch (status) {
  'held' => 'Earnings pending',
  'disputed' => 'On hold',
  'released' => 'Available',
  'refunded' => 'Refunded',
  _ => 'Payment update',
};

String sellerEscrowStatusHint(String status) => switch (status) {
  'held' => 'Waiting for order completion',
  'disputed' => 'Waiting for a delivery-problem decision',
  'released' => 'Ready for payout',
  'refunded' => 'Returned to the buyer',
  _ => '',
};

class SellerEarningsActivity {
  const SellerEarningsActivity({
    required this.escrowId,
    required this.orderId,
    required this.orderNumber,
    required this.title,
    required this.status,
    required this.sellerAmountCentavos,
    this.sortAt,
  });

  final String escrowId;
  final String orderId;
  final String orderNumber;
  final String title;
  final String status;
  final int sellerAmountCentavos;
  final DateTime? sortAt;

  factory SellerEarningsActivity.fromMap(Map<String, dynamic> map) {
    DateTime? parseTime(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return SellerEarningsActivity(
      escrowId: map['escrow_id']?.toString() ?? '',
      orderId: map['order_id']?.toString() ?? '',
      orderNumber: map['order_number']?.toString() ?? '',
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title'] as String
          : 'Order',
      status: map['status']?.toString() ?? '',
      sellerAmountCentavos: readCentavos(map['seller_amount_centavos']),
      sortAt: parseTime(map['sort_at']),
    );
  }
}

enum SellerPayoutStatus { requested, paid, rejected, cancelled }

SellerPayoutStatus sellerPayoutStatusFromRaw(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'paid' => SellerPayoutStatus.paid,
    'rejected' => SellerPayoutStatus.rejected,
    'cancelled' => SellerPayoutStatus.cancelled,
    _ => SellerPayoutStatus.requested,
  };
}

String sellerPayoutStatusLabel(SellerPayoutStatus status) => switch (status) {
  SellerPayoutStatus.requested => 'Waiting for admin',
  SellerPayoutStatus.paid => 'Sent to GCash',
  SellerPayoutStatus.rejected => 'Not approved',
  SellerPayoutStatus.cancelled => 'Cancelled',
};

/// Masks a mobile number to its last four digits, e.g. `•••• 4567`.
String maskMobileNumber(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '';
  return '•••• ${digits.substring(digits.length - 4)}';
}

class SellerPayoutRecord {
  const SellerPayoutRecord({
    required this.payoutId,
    required this.amountCentavos,
    required this.status,
    this.requestedAt,
    this.gcashAccountName,
    this.gcashMobileNumber,
    this.gcashReference,
    this.transferredAmountCentavos,
    this.transferredAt,
    this.rejectionReason,
    this.cancelledAt,
    this.processedAt,
  });

  final String payoutId;
  final int amountCentavos;
  final SellerPayoutStatus status;
  final DateTime? requestedAt;
  final String? gcashAccountName;
  final String? gcashMobileNumber;
  final String? gcashReference;
  final int? transferredAmountCentavos;
  final DateTime? transferredAt;
  final String? rejectionReason;
  final DateTime? cancelledAt;
  final DateTime? processedAt;

  bool get canCancel => status == SellerPayoutStatus.requested;

  factory SellerPayoutRecord.fromMap(Map<String, dynamic> map) {
    DateTime? parseTime(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    String? text(dynamic value) {
      final s = value?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    final transferred = map['transferred_amount_centavos'];
    return SellerPayoutRecord(
      payoutId: map['payout_id']?.toString() ?? '',
      amountCentavos: readCentavos(map['amount_centavos']),
      status: sellerPayoutStatusFromRaw(map['status']?.toString()),
      requestedAt: parseTime(map['requested_at']),
      gcashAccountName: text(map['gcash_account_name']),
      gcashMobileNumber: text(map['gcash_mobile_number']),
      gcashReference: text(map['gcash_reference']),
      transferredAmountCentavos: transferred == null
          ? null
          : readCentavos(transferred),
      transferredAt: parseTime(map['transferred_at']),
      rejectionReason: text(map['rejection_reason']),
      cancelledAt: parseTime(map['cancelled_at']),
      processedAt: parseTime(map['processed_at']),
    );
  }
}

class SellerEarningsSnapshot {
  const SellerEarningsSnapshot({
    required this.heldCentavos,
    required this.releasedCentavos,
    required this.refundedCentavos,
    required this.payoutRequestedCentavos,
    this.payoutPaidCentavos = 0,
    required this.availableCentavos,
    required this.listingCount,
    required this.activity,
    required this.payouts,
  });

  final int heldCentavos;
  final int releasedCentavos;
  final int refundedCentavos;

  /// Payout requests still waiting for an admin transfer.
  final int payoutRequestedCentavos;

  /// Payouts an admin recorded as sent to the seller's GCash.
  final int payoutPaidCentavos;
  final int availableCentavos;
  final int listingCount;
  final List<SellerEarningsActivity> activity;
  final List<SellerPayoutRecord> payouts;

  SellerPayoutRecord? get openPayout {
    for (final p in payouts) {
      if (p.status == SellerPayoutStatus.requested) return p;
    }
    return null;
  }

  bool get hasOpenPayout => openPayout != null;

  bool get canRequestPayout => availableCentavos >= 100 && !hasOpenPayout;

  factory SellerEarningsSnapshot.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> asMaps(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final released = readCentavos(map['released_centavos']);
    final payoutRequested = readCentavos(map['payout_requested_centavos']);
    final payoutPaid = readCentavos(map['payout_paid_centavos']);
    final serverAvailable = map.containsKey('available_centavos')
        ? readCentavos(map['available_centavos'])
        : sellerAvailableCentavos(
            releasedCentavos: released,
            payoutRequestedCentavos: payoutRequested,
            payoutPaidCentavos: payoutPaid,
          );

    return SellerEarningsSnapshot(
      heldCentavos: readCentavos(map['held_centavos']),
      releasedCentavos: released,
      refundedCentavos: readCentavos(map['refunded_centavos']),
      payoutRequestedCentavos: payoutRequested,
      payoutPaidCentavos: payoutPaid,
      availableCentavos: serverAvailable,
      listingCount: readCentavos(map['listing_count']),
      activity: asMaps(
        map['activity'],
      ).map(SellerEarningsActivity.fromMap).toList(),
      payouts: asMaps(map['payouts']).map(SellerPayoutRecord.fromMap).toList(),
    );
  }
}
