import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/seller/data/seller_saved_riders_service.dart';
import 'package:thriftline/models/enums.dart';

void main() {
  final service = SellerSavedRidersService(SupabaseService());

  test('requires plates for motorized vehicle types', () {
    for (final vehicle in [
      DeliveryVehicleType.motorcycle,
      DeliveryVehicleType.car,
      DeliveryVehicleType.van,
    ]) {
      expect(
        service.validateDraft(
          riderName: 'Juan Dela Cruz',
          riderPhone: '09171234567',
          vehicle: vehicle,
          plateNumber: '',
        ),
        'Enter the plate number.',
      );
    }
  });

  test('allows plate-less non-motorized vehicle types', () {
    for (final vehicle in [
      DeliveryVehicleType.bicycle,
      DeliveryVehicleType.other,
    ]) {
      expect(
        service.validateDraft(
          riderName: 'Juan Dela Cruz',
          riderPhone: '09171234567',
          vehicle: vehicle,
          plateNumber: '',
        ),
        isNull,
      );
    }
  });
}
