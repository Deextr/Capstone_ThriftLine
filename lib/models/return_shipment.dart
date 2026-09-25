class ReturnShipment {
  const ReturnShipment({
    required this.id,
    required this.disputeId,
    required this.orderId,
    required this.returnRequired,
    required this.status,
    this.riderName,
    this.riderPhone,
    this.vehicleType,
    this.plateNumber,
    this.notes,
    this.pickupScheduledAt,
    this.pickedUpAt,
    this.returnedAt,
  });

  final String id;
  final String disputeId;
  final String orderId;
  final bool returnRequired;
  final String status;
  final String? riderName;
  final String? riderPhone;
  final String? vehicleType;
  final String? plateNumber;
  final String? notes;
  final DateTime? pickupScheduledAt;
  final DateTime? pickedUpAt;
  final DateTime? returnedAt;

  bool get needsRider =>
      returnRequired &&
      (status == 'waiting_for_rider' || status == 'rider_assigned');

  bool get canHandOff => returnRequired && status == 'rider_assigned';

  bool get canConfirmReceived => returnRequired && status == 'picked_up';

  bool get isOpen =>
      returnRequired &&
      status != 'returned' &&
      status != 'cancelled_by_admin' &&
      status != 'not_required';

  factory ReturnShipment.fromSupabase(Map<String, dynamic> row) {
    DateTime? parseTime(Object? value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return ReturnShipment(
      id: row['return_id'] as String? ?? '',
      disputeId: row['dispute_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      returnRequired: row['return_required'] == true,
      status: row['status'] as String? ?? '',
      riderName: row['rider_name'] as String?,
      riderPhone: row['rider_phone'] as String?,
      vehicleType: row['vehicle_type'] as String?,
      plateNumber: row['plate_number'] as String?,
      notes: row['return_notes'] as String?,
      pickupScheduledAt: parseTime(row['pickup_scheduled_at']),
      pickedUpAt: parseTime(row['picked_up_at']),
      returnedAt: parseTime(row['returned_at']),
    );
  }
}

String returnStatusLabel(String status) => switch (status) {
  'not_required' => 'No return needed',
  'waiting_for_rider' => 'Waiting for rider',
  'rider_assigned' => 'Rider assigned',
  'picked_up' => 'Picked up',
  'returned' => 'Returned',
  'cancelled_by_admin' => 'Return stopped',
  _ => 'Return update',
};

String returnStatusHint(String status) => switch (status) {
  'not_required' => 'You do not need to send the item back.',
  'waiting_for_rider' => 'The seller is responsible for arranging a rider.',
  'rider_assigned' => 'Hand the item to the rider when they arrive.',
  'picked_up' => 'The rider has the item.',
  'returned' => 'The seller confirmed the item was returned.',
  'cancelled_by_admin' =>
    'An admin stopped this return. The refund is unchanged.',
  _ => '',
};

const List<String> kReturnProgressSteps = [
  'Refund approved',
  'Waiting for rider',
  'Rider assigned',
  'Picked up',
  'Returned',
];

int returnProgressIndex(String status) => switch (status) {
  'waiting_for_rider' => 1,
  'rider_assigned' => 2,
  'picked_up' => 3,
  'returned' => 4,
  _ => 0,
};

ReturnShipment? returnShipmentFromOrderRow(Map<String, dynamic> row) {
  final raw = row['item_return'] ?? row['return_shipments'];
  Map<String, dynamic>? map;
  if (raw is Map<String, dynamic>) {
    map = raw;
  } else if (raw is Map) {
    map = Map<String, dynamic>.from(raw);
  } else if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    if (first is Map<String, dynamic>) {
      map = first;
    } else if (first is Map) {
      map = Map<String, dynamic>.from(first);
    }
  }
  if (map == null || (map['return_id'] as String?)?.isNotEmpty != true) {
    return null;
  }
  return ReturnShipment.fromSupabase(map);
}
