import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/listing_limit.dart';

void main() {
  group('seller active listing limit', () {
    test('allows publish below the cap', () {
      expect(sellerCanPublishListing(0), isTrue);
      expect(sellerCanPublishListing(9), isTrue);
    });

    test('blocks publish at the cap', () {
      expect(sellerCanPublishListing(10), isFalse);
      expect(sellerCanPublishListing(11), isFalse);
    });

    test('recognizes backend listing_limit_reached errors', () {
      expect(
        listingLimitMessageFromError(
          Exception('listing_limit_reached: You can have up to 10 active'),
        ),
        kListingLimitReachedMessage,
      );
      expect(
        listingLimitMessageFromError(Exception('network timeout')),
        isNull,
      );
    });
  });
}
