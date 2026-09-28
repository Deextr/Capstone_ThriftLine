import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/stock_limits.dart';
import 'package:thriftline/features/seller/controllers/add_listing_controller.dart';
import 'package:thriftline/models/enums.dart';

void main() {
  group('maxPurchasableQuantityFor', () {
    test('fixed-price follows available stock', () {
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.fixedPrice,
          quantityAvailable: 5,
        ),
        5,
      );
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.fixedPrice,
          quantityAvailable: 1,
        ),
        1,
      );
    });

    test('auction is always 1 when any stock remains', () {
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.auction,
          quantityAvailable: 5,
        ),
        1,
      );
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.auction,
          quantityAvailable: 1,
        ),
        1,
      );
    });

    test('sold listings cannot be purchased', () {
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.fixedPrice,
          quantityAvailable: 0,
        ),
        0,
      );
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.auction,
          quantityAvailable: 0,
        ),
        0,
      );
    });
  });

  group('clampCartQuantity', () {
    test('cannot exceed available stock', () {
      expect(clampCartQuantity(1, 5), 1);
      expect(clampCartQuantity(5, 5), 5);
      expect(clampCartQuantity(6, 5), 5);
      expect(clampCartQuantity(2, 1), 1);
    });

    test('auction-style max of 1 cannot increment', () {
      expect(clampCartQuantity(1, 1), 1);
      expect(clampCartQuantity(2, 1), 1);
    });

    test('returns 0 when nothing is left', () {
      expect(clampCartQuantity(2, 0), 0);
    });
  });

  group('stockShortageMessage', () {
    test('explains remaining stock after another buyer purchases', () {
      expect(
        stockShortageMessage(title: 'Nike T-Shirt', requested: 2, available: 1),
        'Available stock has changed. Only 1 left of Nike T-Shirt. '
        'Update the quantity and try again.',
      );
    });

    test('explains a sold-out listing', () {
      expect(
        stockShortageMessage(title: 'Nike T-Shirt', requested: 1, available: 0),
        'Nike T-Shirt is no longer available.',
      );
    });

    test('is silent when quantity is within stock', () {
      expect(
        stockShortageMessage(title: 'Nike T-Shirt', requested: 3, available: 5),
        isNull,
      );
    });
  });

  group('listingQuantityAvailable', () {
    test('auction stock is always 1', () {
      expect(listingQuantityAvailable(ListingFormat.auction, '8'), 1);
      expect(listingQuantityAvailable(ListingFormat.auction, ''), 1);
    });

    test('fixed-price uses the seller stock field', () {
      expect(listingQuantityAvailable(ListingFormat.fixedPrice, '5'), 5);
      expect(listingQuantityAvailable(ListingFormat.fixedPrice, ' 3 '), 3);
    });
  });

  group('listingStockIsValid', () {
    test('auction does not require a stock field', () {
      expect(listingStockIsValid(ListingFormat.auction, ''), isTrue);
    });

    test('fixed-price requires at least 1 on create', () {
      expect(listingStockIsValid(ListingFormat.fixedPrice, '1'), isTrue);
      expect(listingStockIsValid(ListingFormat.fixedPrice, '0'), isFalse);
      expect(listingStockIsValid(ListingFormat.fixedPrice, 'abc'), isFalse);
    });

    test('edit listing may keep zero remaining stock', () {
      expect(
        listingStockIsValid(ListingFormat.fixedPrice, '0', min: 0),
        isTrue,
      );
    });
  });
}
