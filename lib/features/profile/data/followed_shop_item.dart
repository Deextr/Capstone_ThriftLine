import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';

/// Represents a followed seller shop with its profile metadata,
/// follow timestamp, and preview products.
class FollowedShopItem {
  const FollowedShopItem({
    required this.profile,
    this.previewProducts = const [],
    this.followedAt,
  });

  final SellerProfile profile;
  final List<ProductModel> previewProducts;
  final DateTime? followedAt;

  String get sellerId => profile.sellerId ?? '';
  String get username => profile.username;
  String get shopName => profile.shopName;
  String get ownerName => profile.ownerName;
  String get avatarUrl => profile.avatarUrl;
  String? get bannerUrl => profile.bannerUrl;
  double get rating => profile.rating;
  int get ratingCount => profile.ratingCount;
  int get sales => profile.sales;
  int get itemCount => profile.itemCount;
  bool get isVerified => profile.isVerified;
  String get location => profile.location;
  int get trustScore => profile.trustScore;
  String? get trustLevel => profile.trustLevel;
  String? get shopBio => profile.shopBio;
  int get followerCount => profile.followerCount;

  FollowedShopItem copyWith({
    SellerProfile? profile,
    List<ProductModel>? previewProducts,
    DateTime? followedAt,
  }) {
    return FollowedShopItem(
      profile: profile ?? this.profile,
      previewProducts: previewProducts ?? this.previewProducts,
      followedAt: followedAt ?? this.followedAt,
    );
  }
}
