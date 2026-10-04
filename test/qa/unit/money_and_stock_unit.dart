import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/cart_popularity.dart';
import 'package:thriftline/core/utils/money.dart';
import 'package:thriftline/core/utils/stock_limits.dart';
import 'package:thriftline/models/enums.dart';

import '../support/qa_reporter.dart';

void moneyAndStockUnitTests() {
  qaGroup('Money', () {
    qaUnitTest('phpPesosToCentavos converts pesos to centavos', () {
      expect(phpPesosToCentavos(150), 15000);
      expect(phpPesosToCentavos(99.99), 9999);
      expect(phpPesosToCentavos(1.10), 110);
      expect(phpPesosToCentavos(0), 0);
    });

    qaUnitTest('phpPesosToCentavos guards NaN and infinity', () {
      expect(phpPesosToCentavos(double.nan), 0);
      expect(phpPesosToCentavos(double.infinity), 0);
      expect(phpPesosToCentavos(double.negativeInfinity), 0);
    });
  });

  qaGroup('Cart popularity', () {
    qaUnitTest('hides zero and negative counts', () {
      expect(formatCartPopularity(0), isNull);
      expect(formatCartPopularity(-3), isNull);
    });

    qaUnitTest('uses exact counts then 5+, 10+, 50+ buckets', () {
      expect(formatCartPopularity(1), '1');
      expect(formatCartPopularity(4), '4');
      expect(formatCartPopularity(5), '5+');
      expect(formatCartPopularity(9), '5+');
      expect(formatCartPopularity(10), '10+');
      expect(formatCartPopularity(49), '10+');
      expect(formatCartPopularity(50), '50+');
      expect(formatCartPopularity(1000), '50+');
    });
  });

  qaGroup('Stock limits', () {
    qaUnitTest('auctions can only be bought once', () {
      expect(
        maxPurchasableQuantityFor(
          sellingType: SellingType.auction,
          quantityAvailable: 5,
        ),
        1,
      );
    });

    qaUnitTest('fixed-price uses live stock and never goes negative', () {
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
          quantityAvailable: -2,
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

    qaUnitTest('clampCartQuantity keeps quantity within 1..max', () {
      expect(clampCartQuantity(3, 0), 0);
      expect(clampCartQuantity(0, 5), 1);
      expect(clampCartQuantity(-4, 5), 1);
      expect(clampCartQuantity(8, 5), 5);
      expect(clampCartQuantity(3, 5), 3);
    });

    qaUnitTest('stockShortageMessage explains sold-out and low stock', () {
      expect(
        stockShortageMessage(title: '  ', requested: 1, available: 0),
        'This item is no longer available.',
      );
      expect(
        stockShortageMessage(
          title: 'Denim Jacket',
          requested: 3,
          available: 2,
        ),
        'Available stock has changed. Only 2 left of Denim Jacket. '
        'Update the quantity and try again.',
      );
      expect(
        stockShortageMessage(title: 'Denim', requested: 2, available: 5),
        isNull,
      );
    });

    qaUnitTest('only fixed-price and "both" listings use the cart', () {
      expect(listingUsesShoppingCart(SellingType.fixedPrice), isTrue);
      expect(listingUsesShoppingCart(SellingType.both), isTrue);
      expect(listingUsesShoppingCart(SellingType.auction), isFalse);
      expect(listingUsesShoppingCart(SellingType.liveSession), isFalse);
    });
  });
}
