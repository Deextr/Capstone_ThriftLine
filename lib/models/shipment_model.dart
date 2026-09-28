import '../core/utils/ph_phone.dart';
import '../core/utils/rider_privacy.dart';
import 'enums.dart';

class ShipmentModel {
  const ShipmentModel({
    required this.id,
    required this.orderId,
    required this.deliveryStatus,
    this.deliveryMethod = 'freelance_rider',
    this.riderName,
    this.riderPhone,
    this.vehicleType,
    this.plateNumber,
    this.deliveryNotes,
    this.estimatedDeliveryAt,
    this.riderAssignedAt,
    this.readyForPickupAt,
    this.pickedUpAt,
    this.outForDeliveryAt,
    this.deliveryPinExpiresAt,
    this.deliveryPinAttempts = 0,
    this.deliveryPinLockedUntil,
    this.deliveryPinUsedAt,
    this.deliveryVerifiedAt,
    this.deliveryVerificationMethod,
    this.buyerConfirmedReceived = false,
    this.buyerConfirmedReceivedAt,
    this.inspectionStartedAt,
    this.inspectionExpiresAt,
    this.deliveryFailedAt,
    this.deliveryFailureReason,
    this.autoCompleted = false,
    this.completionReason,
    this.completedAt,
  });

  final String id;
  final String orderId;
  final DeliveryStatus deliveryStatus;
  final String deliveryMethod;
  final String? riderName;
  final String? riderPhone;
  final String? vehicleType;
  final String? plateNumber;
  final String? deliveryNotes;
  final DateTime? estimatedDeliveryAt;
  final DateTime? riderAssignedAt;
  final DateTime? readyForPickupAt;
  final DateTime? pickedUpAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveryPinExpiresAt;
  final int deliveryPinAttempts;
  final DateTime? deliveryPinLockedUntil;
  final DateTime? deliveryPinUsedAt;
  final DateTime? deliveryVerifiedAt;
  final String? deliveryVerificationMethod;
  final bool buyerConfirmedReceived;
  final DateTime? buyerConfirmedReceivedAt;
  final DateTime? inspectionStartedAt;
  final DateTime? inspectionExpiresAt;
  final DateTime? deliveryFailedAt;
  final DeliveryFailureReason? deliveryFailureReason;
  final bool autoCompleted;
  final String? completionReason;
  final DateTime? completedAt;

  /// A rider is considered assigned only when the shipment contains rider
  /// identity data. A progressed status alone is not enough: it can be a
  /// courier shipment or a stale row and must not reveal contact controls.
  bool get hasRider =>
      (riderName != null && riderName!.trim().isNotEmpty) || hasRiderPhone;

  bool get isLocalRider =>
      deliveryMethod.trim().toLowerCase() == 'freelance_rider' ||
      deliveryMethod.trim().toLowerCase() == 'local_rider';

  bool get isOfficialCourier => !isLocalRider;

  bool get hasRiderPhone => normalizePhMobile(riderPhone) != null;

  /// Rider information is relevant to a buyer only while the rider is
  /// responsible for the parcel. After hand-off/verification, the contact
  /// controls disappear instead of exposing a number indefinitely.
  bool get hasActiveRider =>
      isLocalRider &&
      switch (deliveryStatus) {
        DeliveryStatus.riderAssigned ||
        DeliveryStatus.readyForPickup ||
        DeliveryStatus.pickedUp ||
        DeliveryStatus.outForDelivery ||
        DeliveryStatus.awaitingDeliveryVerification => true,
        _ => false,
      };

  bool get shouldShowBuyerRiderInfo => hasActiveRider && hasRider;

  bool get isRiderContactVisibleToBuyer =>
      shouldShowBuyerRiderInfo && hasRiderPhone;

  bool get canEditRider =>
      deliveryVerifiedAt == null &&
      deliveryStatus != DeliveryStatus.inspectionPeriod &&
      deliveryStatus != DeliveryStatus.completed &&
      deliveryStatus != DeliveryStatus.cancelled &&
      deliveryStatus != DeliveryStatus.disputed &&
      deliveryStatus != DeliveryStatus.deliveryFailed;

  bool get isOutForDelivery =>
      deliveryStatus == DeliveryStatus.outForDelivery ||
      deliveryStatus == DeliveryStatus.awaitingDeliveryVerification;

  bool get pinAvailable =>
      isOutForDelivery &&
      deliveryVerifiedAt == null &&
      deliveryPinUsedAt == null;

  bool get isVerified => deliveryVerifiedAt != null;

  bool get isInspecting => deliveryStatus.isInspecting;

  bool get isFailed => deliveryStatus == DeliveryStatus.deliveryFailed;

  bool get isDisputed => deliveryStatus == DeliveryStatus.disputed;

  bool get isCompleted => deliveryStatus == DeliveryStatus.completed;

  String get vehicleLabel {
    if (vehicleType == null || vehicleType!.isEmpty) return 'Not set';
    return DeliveryVehicleType.fromDb(vehicleType).label;
  }

  String buyerRiderName() {
    final name = riderName?.trim() ?? '';
    return maskRiderName(name);
  }

  /// Full rider name for the buyer's active delivery. The older
  /// [buyerRiderName] helper remains available for legacy privacy displays;
  /// tracking uses this value because the assigned rider is directly
  /// responsible for coordinating the delivery.
  String buyerRiderDisplayName() {
    final name = riderName?.trim() ?? '';
    return name.isEmpty ? 'Delivery rider' : name;
  }

  String buyerRiderPhone() => formatPhMobile(riderPhone);

  String sellerRiderPhone() => maskRiderPhone(riderPhone, sellerView: true);

  factory ShipmentModel.fromSupabase(Map<String, dynamic> row) {
    return ShipmentModel(
      id: row['shipment_id'] as String? ?? row['id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      deliveryStatus: DeliveryStatus.fromDb(row['delivery_status'] as String?),
      deliveryMethod: row['delivery_method'] as String? ?? 'freelance_rider',
      riderName: row['rider_name'] as String?,
      riderPhone: row['rider_phone'] as String?,
      vehicleType: row['vehicle_type'] as String?,
      plateNumber: row['plate_number'] as String?,
      deliveryNotes: row['delivery_notes'] as String?,
      estimatedDeliveryAt: _parseTime(row['estimated_delivery_at']),
      riderAssignedAt: _parseTime(row['rider_assigned_at']),
      readyForPickupAt: _parseTime(row['ready_for_pickup_at']),
      pickedUpAt: _parseTime(row['picked_up_at']),
      outForDeliveryAt: _parseTime(row['out_for_delivery_at']),
      deliveryPinExpiresAt: _parseTime(row['delivery_pin_expires_at']),
      deliveryPinAttempts: (row['delivery_pin_attempts'] as num?)?.toInt() ?? 0,
      deliveryPinLockedUntil: _parseTime(row['delivery_pin_locked_until']),
      deliveryPinUsedAt: _parseTime(row['delivery_pin_used_at']),
      deliveryVerifiedAt: _parseTime(row['delivery_verified_at']),
      deliveryVerificationMethod:
          row['delivery_verification_method'] as String?,
      buyerConfirmedReceived: row['buyer_confirmed_received'] as bool? ?? false,
      buyerConfirmedReceivedAt: _parseTime(row['buyer_confirmed_received_at']),
      inspectionStartedAt: _parseTime(row['inspection_started_at']),
      inspectionExpiresAt: _parseTime(row['inspection_expires_at']),
      deliveryFailedAt: _parseTime(row['delivery_failed_at']),
      deliveryFailureReason: DeliveryFailureReason.fromDb(
        row['delivery_failure_reason'] as String?,
      ),
      autoCompleted: row['auto_completed'] as bool? ?? false,
      completionReason: row['completion_reason'] as String?,
      completedAt: _parseTime(row['completed_at']),
    );
  }
}

DateTime? _parseTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

ShipmentModel? shipmentFromOrderRow(Map<String, dynamic> row) {
  final raw = row['shipment'] ?? row['shipments'];
  if (raw is Map<String, dynamic>) {
    return ShipmentModel.fromSupabase(raw);
  }
  if (raw is Map) {
    return ShipmentModel.fromSupabase(Map<String, dynamic>.from(raw));
  }
  if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    if (first is Map<String, dynamic>) {
      return ShipmentModel.fromSupabase(first);
    }
    if (first is Map) {
      return ShipmentModel.fromSupabase(Map<String, dynamic>.from(first));
    }
  }
  return null;
}
