import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/data/order_query.dart';
import 'package:thriftline/features/seller/controllers/add_listing_controller.dart';

void main() {
  group('SEL-002 shipment client projection', () {
    test('order shipment select omits delivery_pin_hash', () {
      expect(kShipmentSelect, isNot(contains('delivery_pin_hash')));
    });
  });

  group('SEL-003 product validation alignment', () {
    test('fixed-price stock accepts 1 through 9999', () {
      expect(listingStockIsValid(ListingFormat.fixedPrice, '1'), isTrue);
      expect(listingStockIsValid(ListingFormat.fixedPrice, '9999'), isTrue);
      expect(listingStockIsValid(ListingFormat.fixedPrice, '0'), isFalse);
      expect(listingStockIsValid(ListingFormat.fixedPrice, '10000'), isFalse);
    });
  });
}
