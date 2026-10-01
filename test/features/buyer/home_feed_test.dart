import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/cart_popularity.dart';
import 'package:thriftline/features/buyer/data/home_feed_query.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';

void main() {
  group('formatCartPopularity', () {
    test('hides zero and negatives', () {
      expect(formatCartPopularity(0), isNull);
      expect(formatCartPopularity(-3), isNull);
    });

    test('uses compact ranges', () {
      expect(formatCartPopularity(1), '1');
      expect(formatCartPopularity(4), '4');
      expect(formatCartPopularity(5), '5+');
      expect(formatCartPopularity(9), '5+');
      expect(formatCartPopularity(10), '10+');
      expect(formatCartPopularity(49), '10+');
      expect(formatCartPopularity(50), '50+');
      expect(formatCartPopularity(120), '50+');
    });
  });

  group('sortProductsByIdOrder', () {
    ProductModel product(String id) => ProductModel(
      id: id,
      sellerUsername: 'shop',
      sellerName: 'Shop',
      sellerAvatar: '',
      sellerVerified: false,
      title: id,
      description: '',
      price: 100,
      category: ProductCategory.tops,
      condition: ProductCondition.good,
      createdAt: DateTime(2026, 1, 1),
    );

    test('keeps the requested id order and drops missing ids', () {
      final sorted = sortProductsByIdOrder(
        [product('b'), product('a')],
        ['a', 'missing', 'b'],
      );
      expect(sorted.map((p) => p.id), ['a', 'b']);
    });
  });

  group('isHomeOfflineError', () {
    test('detects dropped connections', () {
      expect(
        isHomeOfflineError(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(isHomeOfflineError(Exception('permission denied')), isFalse);
    });
  });

  group('isLiveBuyerHomeListing', () {
    ProductModel auction({required DateTime end}) => ProductModel(
      id: 'a1',
      sellerUsername: 'shop',
      sellerName: 'Shop',
      sellerAvatar: '',
      sellerVerified: false,
      title: 'Jacket',
      description: '',
      price: 100,
      category: ProductCategory.tops,
      condition: ProductCondition.good,
      createdAt: DateTime(2026, 1, 1),
      sellingType: SellingType.auction,
      bidEndTime: end,
      currentBid: 200,
    );

    test('keeps live auctions and hides ended ones', () {
      expect(
        isLiveBuyerHomeListing(
          auction(end: DateTime.now().add(const Duration(hours: 2))),
        ),
        isTrue,
      );
      expect(
        isLiveBuyerHomeListing(
          auction(end: DateTime.now().subtract(const Duration(minutes: 1))),
        ),
        isFalse,
      );
    });
  });
}
