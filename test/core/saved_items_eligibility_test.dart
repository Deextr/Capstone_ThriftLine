import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/saved_items_eligibility.dart';

void main() {
  group('canShowProductFavoriteAction', () {
    test('buyer can favorite another seller listing', () {
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: true,
          viewerUserId: 'buyer-1',
          productSellerId: 'seller-2',
        ),
        isTrue,
      );
    });

    test('buyer cannot favorite own listing', () {
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: true,
          viewerUserId: 'user-1',
          productSellerId: 'user-1',
        ),
        isFalse,
      );
    });

    test('seller workspace hides favorite even for others listings', () {
      expect(
        canShowProductFavoriteAction(
          isBuyerExperience: false,
          viewerUserId: 'user-1',
          productSellerId: 'seller-2',
        ),
        isFalse,
      );
    });
  });

  group('canPersistProductSave', () {
    test('rejects self-owned product', () {
      expect(
        canPersistProductSave(
          viewerUserId: 'user-1',
          productSellerId: 'user-1',
        ),
        isFalse,
      );
    });
  });
}
