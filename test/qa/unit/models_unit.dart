import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/address_model.dart';
import 'package:thriftline/models/cart_item_model.dart';

import '../support/qa_reporter.dart';

void modelsUnitTests() {
  qaGroup('AddressModel', () {
    qaUnitTest('fromJson reads every Supabase column', () {
      final address = AddressModel.fromJson({
        'address_id': 'addr-1',
        'user_id': 'user-1',
        'recipient_name': 'Dexter Ramos',
        'phone_number': '09171234567',
        'street_address': '123 Rizal St',
        'barangay': 'Poblacion',
        'city': 'Davao City',
        'postal_code': '8000',
        'landmark': 'Near the church',
        'is_default': true,
      });

      expect(address.id, 'addr-1');
      expect(address.userId, 'user-1');
      expect(address.recipientName, 'Dexter Ramos');
      expect(address.landmark, 'Near the church');
      expect(address.isDefault, isTrue);
    });

    qaUnitTest('fromJson applies defaults for missing columns', () {
      final address = AddressModel.fromJson({
        'address_id': 'addr-2',
        'user_id': 'user-1',
      });

      expect(address.recipientName, '');
      expect(address.city, 'Davao City');
      expect(address.postalCode, isNull);
      expect(address.isDefault, isFalse);
    });

    qaUnitTest('formatted joins non-empty parts with commas', () {
      const full = AddressModel(
        id: 'a',
        userId: 'u',
        recipientName: 'R',
        phoneNumber: '09171234567',
        streetAddress: '123 Rizal St',
        barangay: 'Poblacion',
        city: 'Davao City',
        postalCode: '8000',
        isDefault: false,
      );
      const noPostal = AddressModel(
        id: 'a',
        userId: 'u',
        recipientName: 'R',
        phoneNumber: '09171234567',
        streetAddress: '123 Rizal St',
        barangay: '',
        city: 'Davao City',
        postalCode: '  ',
        isDefault: false,
      );

      expect(full.formatted, '123 Rizal St, Poblacion, Davao City, 8000');
      expect(noPostal.formatted, '123 Rizal St, Davao City');
    });

    qaUnitTest('hasValidPhoneContact requires the 09 format', () {
      AddressModel withPhone(String phone) => AddressModel(
        id: 'a',
        userId: 'u',
        recipientName: 'R',
        phoneNumber: phone,
        streetAddress: 's',
        barangay: 'b',
        city: 'c',
        isDefault: false,
      );

      expect(withPhone('09171234567').hasValidPhoneContact, isTrue);
      expect(withPhone('+639171234567').hasValidPhoneContact, isFalse);
      expect(withPhone('').hasValidPhoneContact, isFalse);
    });
  });

  qaGroup('CartItemModel', () {
    qaUnitTest('item without a product has zero price and no type', () {
      const item = CartItemModel(
        id: 'c1',
        userId: 'u1',
        productId: 'p1',
        quantity: 3,
      );

      expect(item.price, 0);
      expect(item.subtotal, 0);
      expect(item.isFixedPrice, isFalse);
      expect(item.isAuction, isFalse);
    });

    qaUnitTest('fromJson supports id fallback, numeric qty and dates', () {
      final item = CartItemModel.fromJson({
        'id': 'legacy-1',
        'user_id': 'u1',
        'product_id': 'p1',
        'quantity': 2.0,
        'created_at': '2026-10-04T07:00:00Z',
      });

      expect(item.id, 'legacy-1');
      expect(item.quantity, 2);
      expect(item.createdAt, DateTime.utc(2026, 10, 4, 7));
      expect(item.updatedAt, isNull);
      expect(item.product, isNull);
    });

    qaUnitTest('fromJson defaults quantity to 1', () {
      final item = CartItemModel.fromJson({'cart_item_id': 'c1'});
      expect(item.id, 'c1');
      expect(item.quantity, 1);
      expect(item.userId, '');
    });

    qaUnitTest('copyWith changes only the given fields', () {
      const item = CartItemModel(id: 'c1', userId: 'u1', productId: 'p1');
      final updated = item.copyWith(quantity: 4);

      expect(updated.quantity, 4);
      expect(updated.id, 'c1');
      expect(updated.productId, 'p1');
    });

    qaUnitTest('toJson omits null timestamps', () {
      const item = CartItemModel(
        id: 'c1',
        userId: 'u1',
        productId: 'p1',
        quantity: 2,
      );

      expect(item.toJson(), {
        'cart_item_id': 'c1',
        'user_id': 'u1',
        'product_id': 'p1',
        'quantity': 2,
      });
    });
  });
}
