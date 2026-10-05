import '../../../core/utils/rider_privacy.dart';
import '../../../models/enums.dart';

/// Reusable rider template owned by a seller (`seller_saved_riders`).
class SellerSavedRider {
  const SellerSavedRider({
    required this.id,
    required this.sellerId,
    required this.riderName,
    required this.riderPhone,
    required this.vehicleType,
    required this.plateNumber,
    this.defaultDeliveryNotes,
  });

  final String id;
  final String sellerId;
  final String riderName;
  final String riderPhone;
  final String vehicleType;
  final String plateNumber;
  final String? defaultDeliveryNotes;

  DeliveryVehicleType get vehicle => DeliveryVehicleType.fromDb(vehicleType);

  String get maskedPhone => maskRiderPhone(riderPhone, sellerView: true);

  factory SellerSavedRider.fromRow(Map<String, dynamic> row) {
    return SellerSavedRider(
      id: row['saved_rider_id'] as String,
      sellerId: row['seller_id'] as String,
      riderName: (row['rider_name'] as String?)?.trim() ?? '',
      riderPhone: (row['rider_phone'] as String?)?.trim() ?? '',
      vehicleType: (row['vehicle_type'] as String?)?.trim() ?? 'motorcycle',
      plateNumber: (row['plate_number'] as String?)?.trim() ?? '',
      defaultDeliveryNotes: (row['default_delivery_notes'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toInsertPayload({required String sellerId}) {
    return {
      'seller_id': sellerId,
      'rider_name': riderName,
      'rider_phone': riderPhone,
      'vehicle_type': vehicleType,
      'plate_number': plateNumber,
      if (defaultDeliveryNotes != null && defaultDeliveryNotes!.isNotEmpty)
        'default_delivery_notes': defaultDeliveryNotes,
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'rider_name': riderName,
      'rider_phone': riderPhone,
      'vehicle_type': vehicleType,
      'plate_number': plateNumber,
      'default_delivery_notes': defaultDeliveryNotes,
    };
  }
}
