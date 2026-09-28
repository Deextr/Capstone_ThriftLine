import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/controllers/buyer_search_controller.dart';
import 'package:thriftline/features/buyer/controllers/looking_for_controller.dart';
import 'package:thriftline/features/buyer/data/catalog_product_query.dart';
import 'package:thriftline/features/chat/data/conversation_service.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/looking_for_model.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/models/seller_profile.dart';

void main() {
  group('catalog search sanitization', () {
    test('strips PostgREST or() metacharacters', () {
      expect(sanitizeCatalogSearchQuery('tee, (50%)'), 'tee 50');
      expect(catalogIlikeOrFilter('tee'), contains('name.ilike.%tee%'));
      expect(isUniqueViolation(Exception('duplicate key value 23505')), isTrue);
    });
  });

  group('ProductModel.fromSupabase catalog fields', () {
    Map<String, dynamic> row({String? name, String? title}) => {
      'product_id': 'p1',
      'seller_id': 's1',
      'name': ?name,
      'title': ?title,
      'price': 250,
      'condition': 'good',
      'listing_type': 'fixed_price',
      'status': 'active',
      'created_at': '2026-09-01T00:00:00Z',
      'images': <dynamic>[],
    };

    test('reads name when the products.title column was renamed', () {
      final product = ProductModel.fromSupabase(row(name: 'Vintage Tee'));
      expect(product.title, 'Vintage Tee');
    });

    test('falls back to title for older rows', () {
      final product = ProductModel.fromSupabase(row(title: 'Legacy Title'));
      expect(product.title, 'Legacy Title');
    });

    test('does not invent an auction end time without an auctions row', () {
      final product = ProductModel.fromSupabase({
        ...row(name: 'Auction bag'),
        'listing_type': 'auction',
      });
      expect(product.hasActiveBid, isFalse);
      expect(product.bidEndTime, isNull);
    });

    test('reads seller username from sellerProfile.user', () {
      final product = ProductModel.fromSupabase(
        row(name: 'Vintage Tee'),
        sellerProfile: {
          'shop_name': 'Retro Rack',
          'is_approved': true,
          'user': {
            'user_id': 's1',
            'username': 'retrorack',
            'full_name': 'Ana Seller',
            'avatar': 'https://example.com/a.png',
            'role': 'seller',
          },
        },
      );
      expect(product.sellerName, 'Retro Rack');
      expect(product.sellerUsername, 'retrorack');
      expect(product.sellerVerified, isTrue);
    });

    test('skips product images that have a null url', () {
      final product = ProductModel.fromSupabase({
        ...row(name: 'Tee'),
        'images': [
          {'image_url': null, 'is_primary': true, 'display_order': 0},
          {
            'image_url': 'https://example.com/tee.jpg',
            'is_primary': false,
            'display_order': 1,
          },
        ],
      });
      expect(product.imageUrls, ['https://example.com/tee.jpg']);
    });
  });

  group('LookingForModel.fromSupabase', () {
    test('maps open to the active Flutter status', () {
      final post = LookingForModel.fromSupabase({
        'post_id': 'lf1',
        'user_id': 'u1',
        'title': 'Need a denim jacket',
        'description': 'Size M',
        'minimum_price': 200,
        'maximum_price': 800,
        'location': 'Davao City',
        'status': 'open',
        'response_count': 0,
        'created_at': '2026-09-01T00:00:00Z',
      });
      expect(post.status, LookingForStatus.active);
      expect(post.title, 'Need a denim jacket');
    });

    test('maps reference_image_url onto thumbnailUrl', () {
      final post = LookingForModel.fromSupabase({
        'post_id': 'lf1',
        'user_id': 'u1',
        'title': 'Need a denim jacket',
        'status': 'open',
        'created_at': '2026-09-01T00:00:00Z',
        'reference_image_url': 'https://example.com/ref.jpg',
      });
      expect(post.thumbnailUrl, 'https://example.com/ref.jpg');
    });
  });

  group('recordRecentSearch', () {
    test('moves a repeat query to the front without duplicating', () {
      expect(recordRecentSearch(['denim', 'y2k'], 'Denim'), ['Denim', 'y2k']);
    });

    test('ignores blank queries and caps the list', () {
      expect(recordRecentSearch(['denim'], '  '), ['denim']);
      expect(recordRecentSearch(['a', 'b', 'c'], 'd', max: 3), ['d', 'a', 'b']);
    });
  });

  group('SellerProfile.fromSupabase ratings', () {
    test('does not invent a 5.0 rating when none exist', () {
      final profile = SellerProfile.fromSupabase(
        {'seller_id': 's1', 'shop_name': 'Retro Rack'},
        userRow: {
          'user_id': 's1',
          'username': 'retrorack',
          'full_name': 'Ana Seller',
        },
      );
      expect(profile.rating, 0);
      expect(profile.ratingCount, 0);
    });
  });

  group('Looking For list placeholder', () {
    test('does not treat the first load as empty', () {
      expect(lookingForShowsEmpty(isLoading: true, postCount: 0), isFalse);
      expect(lookingForShowsEmpty(isLoading: false, postCount: 0), isTrue);
      expect(lookingForShowsEmpty(isLoading: false, postCount: 2), isFalse);
    });
  });

  group('conversation pairing and share copy', () {
    test('orders participant ids so a is always less than b', () {
      final pair = orderedParticipantPair(
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      expect(pair.a.compareTo(pair.b), lessThan(0));
    });

    test('share body keeps the original request title', () {
      final post = LookingForModel.fromSupabase(
        {
          'post_id': 'lf1',
          'user_id': 'u1',
          'title': 'Black Nike jacket',
          'preferred_size': 'M',
          'status': 'open',
          'created_at': '2026-09-01T00:00:00Z',
        },
        buyer: {'full_name': 'Buyer 1'},
      );
      expect(lookingForShareBody(post), contains('Buyer 1 is looking for:'));
      expect(lookingForShareBody(post), contains('Black Nike jacket'));
      expect(lookingForShareBody(post), contains('size M'));
    });

    test('looking_for message type round-trips the db value', () {
      expect(MessageType.lookingFor.dbValue, 'looking_for');
      expect(MessageType.fromString('looking_for'), MessageType.lookingFor);
    });
  });
}
