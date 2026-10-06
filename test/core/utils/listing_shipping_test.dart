import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/listing_shipping.dart';
import 'package:thriftline/models/product_model.dart';
void main() {
  group('calculateShopFixedShippingPreview', () {
    test('all free lines', () {
      final fee = calculateShopFixedShippingPreview([
        const CartShippingLine(
          productId: 'a',
          quantity: 2,
          mode: ListingShippingMode.free,
          shippingFee: 0,
        ),
      ]);
      expect(fee, 0);
    });

    test('fixed fee when below quantity threshold', () {
      final fee = calculateShopFixedShippingPreview([
        CartShippingLine(
          productId: 'a',
          quantity: 2,
          mode: ListingShippingMode.quantityThreshold,
          shippingFee: 80,
          freeShippingQtyThreshold: 3,
        ),
      ]);
      expect(fee, 80);
    });

    test('free when same-product quantity meets threshold', () {
      final fee = calculateShopFixedShippingPreview([
        CartShippingLine(
          productId: 'a',
          quantity: 3,
          mode: ListingShippingMode.quantityThreshold,
          shippingFee: 80,
          freeShippingQtyThreshold: 3,
        ),
      ]);
      expect(fee, 0);
    });

    test('free when different products same shop meet threshold', () {
      final fee = calculateShopFixedShippingPreview([
        CartShippingLine(
          productId: 'a',
          quantity: 1,
          mode: ListingShippingMode.quantityThreshold,
          shippingFee: 60,
          freeShippingQtyThreshold: 3,
        ),
        CartShippingLine(
          productId: 'b',
          quantity: 2,
          mode: ListingShippingMode.fixedFee,
          shippingFee: 100,
        ),
      ]);
      expect(fee, 0);
    });

    test('uses max fee among paid modes when not free', () {
      final fee = calculateShopFixedShippingPreview([
        CartShippingLine(
          productId: 'a',
          quantity: 1,
          mode: ListingShippingMode.fixedFee,
          shippingFee: 60,
        ),
        CartShippingLine(
          productId: 'b',
          quantity: 1,
          mode: ListingShippingMode.fixedFee,
          shippingFee: 100,
        ),
      ]);
      expect(fee, 100);
    });
  });

  group('previewAuctionShipping', () {
    test('free mode', () {
      expect(
        previewAuctionShipping(
          mode: ListingShippingMode.free,
          winningBid: 400,
          shippingFee: 80,
        ),
        0,
      );
    });

    test('below bid threshold', () {
      expect(
        previewAuctionShipping(
          mode: ListingShippingMode.bidThreshold,
          winningBid: 450,
          shippingFee: 80,
          freeShippingBidThreshold: 500,
        ),
        80,
      );
    });

    test('at bid threshold', () {
      expect(
        previewAuctionShipping(
          mode: ListingShippingMode.bidThreshold,
          winningBid: 500,
          shippingFee: 80,
          freeShippingBidThreshold: 500,
        ),
        0,
      );
    });
  });

  group('public item location', () {
    test('hidden when toggle off', () {
      final product = ProductModel.fromSupabase(
        {
          'product_id': 'p1',
          'name': 'Item',
          'price': 100,
          'condition': 'good',
          'listing_type': 'fixed_price',
          'show_item_location': false,
        },
        sellerProfile: {'barangay': 'Pampanga', 'is_approved': true},
      );
      expect(product.publicItemLocation, isNull);
    });

    test('shows barangay and city only', () {
      final product = ProductModel.fromSupabase(
        {
          'product_id': 'p1',
          'name': 'Item',
          'price': 100,
          'condition': 'good',
          'listing_type': 'fixed_price',
          'show_item_location': true,
        },
        sellerProfile: {'barangay': 'Pampanga', 'city': 'Davao City'},
      );
      expect(product.publicItemLocation, 'Pampanga, Davao City');
    });
  });
}
