import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/profile/controllers/following_shops_controller.dart';
import 'package:thriftline/features/profile/data/followed_shop_item.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/models/seller_profile.dart';
import 'package:thriftline/providers/following_shops_provider.dart';

class MockFollowingShopsProvider extends FollowingShopsProvider {
  MockFollowingShopsProvider(super.supabase);

  List<FollowedShopItem> _mockShops = [];
  int _mockCount = 0;

  void setMockShops(List<FollowedShopItem> shops) {
    _mockShops = shops;
    _mockCount = shops.length;
    notifyListeners();
  }

  @override
  List<FollowedShopItem> get followedShops => _mockShops;

  @override
  int get followingCount => _mockCount;
}

void main() {
  group('FollowingShopsController tests', () {
    late MockFollowingShopsProvider provider;
    late FollowingShopsController controller;

    final dummyProducts = [
      ProductModel(
        id: 'p1',
        sellerId: 's1',
        sellerUsername: 'vintagevault',
        sellerName: 'Vintage Vault',
        sellerAvatar: '',
        sellerVerified: true,
        title: 'Vintage Jacket',
        description: 'Classic denim jacket',
        price: 450,
        category: ProductCategory.outerwear,
        condition: ProductCondition.good,
        createdAt: DateTime.now(),
      ),
    ];

    final shop1 = FollowedShopItem(
      profile: const SellerProfile(
        sellerId: 's1',
        username: 'vintagevault',
        shopName: 'Vintage Vault Davao',
        ownerName: 'Alice',
        avatarUrl: '',
        rating: 4.8,
        ratingCount: 25,
        sales: 50,
        itemCount: 5,
        distanceKm: 0,
        isVerified: true,
        location: 'Davao City',
        trustScore: 85,
      ),
      previewProducts: dummyProducts,
    );

    final shop2 = FollowedShopItem(
      profile: const SellerProfile(
        sellerId: 's2',
        username: 'thriftchic',
        shopName: 'Thrift Chic Manila',
        ownerName: 'Bob',
        avatarUrl: '',
        rating: 4.1,
        ratingCount: 10,
        sales: 12,
        itemCount: 0,
        distanceKm: 0,
        isVerified: false,
        location: 'Manila',
        trustScore: 65,
      ),
      previewProducts: const [],
    );

    final shop3 = FollowedShopItem(
      profile: const SellerProfile(
        sellerId: 's3',
        username: 'denimpro',
        shopName: 'Denim Pro Cebu',
        ownerName: 'Charlie',
        avatarUrl: '',
        rating: 4.9,
        ratingCount: 50,
        sales: 100,
        itemCount: 8,
        distanceKm: 0,
        isVerified: true,
        location: 'Cebu City',
        trustScore: 92,
      ),
      previewProducts: dummyProducts,
    );

    setUp(() {
      provider = MockFollowingShopsProvider(SupabaseService());
      controller = FollowingShopsController(
        supabase: SupabaseService(),
        provider: provider,
      );
      provider.setMockShops([shop1, shop2, shop3]);
    });

    test('returns all shops when filter is all and search is empty', () {
      expect(controller.shops.length, 3);
      expect(controller.totalCount, 3);
    });

    test('filters shops by active listings', () {
      controller.setFilter(FollowingFilter.hasListings);
      expect(controller.shops.length, 2);
      expect(controller.shops.map((s) => s.username), containsAll(['vintagevault', 'denimpro']));
    });

    test('filters shops by top rated', () {
      controller.setFilter(FollowingFilter.topRated);
      expect(controller.shops.length, 2);
      expect(controller.shops.map((s) => s.username), containsAll(['vintagevault', 'denimpro']));
    });

    test('filters shops by high trust', () {
      controller.setFilter(FollowingFilter.highTrust);
      expect(controller.shops.length, 2);
      expect(controller.shops.map((s) => s.username), containsAll(['vintagevault', 'denimpro']));
    });

    test('filters shops by search query matching shop name or username', () {
      controller.setSearchQuery('chic');
      expect(controller.shops.length, 1);
      expect(controller.shops.first.username, 'thriftchic');

      controller.setSearchQuery('cebu');
      expect(controller.shops.length, 1);
      expect(controller.shops.first.username, 'denimpro');

      controller.setSearchQuery('vault');
      expect(controller.shops.length, 1);
      expect(controller.shops.first.username, 'vintagevault');
    });

    test('toggleSearch clears search query when closed', () {
      controller.setSearchQuery('test');
      expect(controller.searchQuery, 'test');
      controller.toggleSearch(false);
      expect(controller.searchQuery, '');
    });
  });
}
