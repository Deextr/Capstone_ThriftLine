import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_saved_rider.dart';

void main() {
  test('fromRow maps seller_saved_riders columns', () {
    final rider = SellerSavedRider.fromRow({
      'saved_rider_id': '11111111-1111-1111-1111-111111111111',
      'seller_id': '22222222-2222-2222-2222-222222222222',
      'rider_name': 'Juan Dela Cruz',
      'rider_phone': '09171234567',
      'vehicle_type': 'motorcycle',
      'plate_number': 'ABC 1234',
      'default_delivery_notes': 'Call on arrival',
    });
    expect(rider.id, '11111111-1111-1111-1111-111111111111');
    expect(rider.riderName, 'Juan Dela Cruz');
    expect(rider.riderPhone, '09171234567');
    expect(rider.vehicle.label, 'Motorcycle');
    expect(rider.plateNumber, 'ABC 1234');
    expect(rider.defaultDeliveryNotes, 'Call on arrival');
    expect(rider.maskedPhone, contains('•'));
  });
}
