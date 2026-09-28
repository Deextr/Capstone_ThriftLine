import 'package:flutter/foundation.dart';

@visibleForTesting
int sellerAvailableCentavos({
  required int releasedCentavos,
  required int payoutRequestedCentavos,
}) {
  final available = releasedCentavos - payoutRequestedCentavos;
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

class SellerPayoutRecord {
  const SellerPayoutRecord({
    required this.payoutId,
    required this.amountCentavos,
    required this.status,
    this.requestedAt,
  });

  final String payoutId;
  final int amountCentavos;
  final String status;
  final DateTime? requestedAt;

  factory SellerPayoutRecord.fromMap(Map<String, dynamic> map) {
    DateTime? parseTime(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return SellerPayoutRecord(
      payoutId: map['payout_id']?.toString() ?? '',
      amountCentavos: readCentavos(map['amount_centavos']),
      status: map['status']?.toString() ?? 'requested',
      requestedAt: parseTime(map['requested_at']),
    );
  }
}

class SellerEarningsSnapshot {
  const SellerEarningsSnapshot({
    required this.heldCentavos,
    required this.releasedCentavos,
    required this.refundedCentavos,
    required this.payoutRequestedCentavos,
    required this.availableCentavos,
    required this.listingCount,
    required this.activity,
    required this.payouts,
  });

  final int heldCentavos;
  final int releasedCentavos;
  final int refundedCentavos;
  final int payoutRequestedCentavos;
  final int availableCentavos;
  final int listingCount;
  final List<SellerEarningsActivity> activity;
  final List<SellerPayoutRecord> payouts;

  bool get canRequestPayout => availableCentavos >= 100;

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
    final serverAvailable = map.containsKey('available_centavos')
        ? readCentavos(map['available_centavos'])
        : sellerAvailableCentavos(
            releasedCentavos: released,
            payoutRequestedCentavos: payoutRequested,
          );

    return SellerEarningsSnapshot(
      heldCentavos: readCentavos(map['held_centavos']),
      releasedCentavos: released,
      refundedCentavos: readCentavos(map['refunded_centavos']),
      payoutRequestedCentavos: payoutRequested,
      availableCentavos: serverAvailable,
      listingCount: readCentavos(map['listing_count']),
      activity: asMaps(
        map['activity'],
      ).map(SellerEarningsActivity.fromMap).toList(),
      payouts: asMaps(map['payouts']).map(SellerPayoutRecord.fromMap).toList(),
    );
  }
}
