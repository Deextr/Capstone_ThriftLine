import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/models/bid_model.dart';
import 'package:thriftline/models/enums.dart';

void main() {
  group('UserBid fromSupabase mapping', () {
    test('parses active winning bid correctly', () {
      final json = {
        'bid_id': 'bid-123',
        'bidder_id': 'user-1',
        'bid_amount': 250.0,
        'is_highest_bid': true,
        'created_at': '2026-09-07T12:00:00Z',
        'auction': {
          'auction_id': 'auc-1',
          'product_id': 'prod-1',
          'starting_price': 100.0,
          'current_price': 250.0,
          'minimum_increment': 20.0,
          'winner_id': 'user-1',
          'ends_at': '2026-09-10T12:00:00Z',
          'status': 'active',
          'product': {
            'product_id': 'prod-1',
            'name': 'Vintage Denim Jacket',
            'price': 250.0,
            'condition': 'good',
            'listing_type': 'auction',
          },
        },
      };

      final bid = UserBid.fromSupabase(json);

      expect(bid.id, equals('bid-123'));
      expect(bid.productId, equals('prod-1'));
      expect(bid.amount, equals(250.0));
      expect(bid.status, equals(BidStatus.winning));
      expect(bid.isHighestBid, isTrue);
      expect(bid.product?.title, equals('Vintage Denim Jacket'));
    });

    test('parses active outbid status correctly', () {
      final json = {
        'bid_id': 'bid-456',
        'bidder_id': 'user-1',
        'bid_amount': 200.0,
        'is_highest_bid': false,
        'created_at': '2026-09-07T10:00:00Z',
        'auction': {
          'auction_id': 'auc-1',
          'product_id': 'prod-1',
          'starting_price': 100.0,
          'current_price': 250.0,
          'minimum_increment': 20.0,
          'winner_id': 'user-2',
          'ends_at': '2026-09-10T12:00:00Z',
          'status': 'active',
        },
      };

      final bid = UserBid.fromSupabase(json);

      expect(bid.status, equals(BidStatus.outbid));
      expect(bid.isHighestBid, isFalse);
    });

    test('parses won auction correctly', () {
      final json = {
        'bid_id': 'bid-789',
        'bidder_id': 'user-1',
        'bid_amount': 300.0,
        'is_highest_bid': true,
        'created_at': '2026-09-01T12:00:00Z',
        'auction': {
          'auction_id': 'auc-2',
          'product_id': 'prod-2',
          'starting_price': 100.0,
          'current_price': 300.0,
          'winner_id': 'user-1',
          'ends_at': '2026-09-05T12:00:00Z',
          'status': 'ended',
        },
      };

      final bid = UserBid.fromSupabase(json);

      expect(bid.status, equals(BidStatus.won));
    });

    test('parses lost auction correctly', () {
      final json = {
        'bid_id': 'bid-999',
        'bidder_id': 'user-1',
        'bid_amount': 150.0,
        'is_highest_bid': false,
        'created_at': '2026-09-01T12:00:00Z',
        'auction': {
          'auction_id': 'auc-3',
          'product_id': 'prod-3',
          'starting_price': 100.0,
          'current_price': 250.0,
          'winner_id': 'user-99',
          'ends_at': '2026-09-05T12:00:00Z',
          'status': 'ended',
        },
      };

      final bid = UserBid.fromSupabase(json);

      expect(bid.status, equals(BidStatus.lost));
    });
  });
}
