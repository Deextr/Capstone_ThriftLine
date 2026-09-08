class SellerProfile {
  const SellerProfile({
    this.sellerId,
    required this.username,
    required this.shopName,
    required this.ownerName,
    required this.avatarUrl,
    this.bannerUrl,
    required this.rating,
    this.ratingCount = 0,
    required this.sales,
    required this.itemCount,
    required this.distanceKm,
    required this.isVerified,
    required this.location,
    this.trustScore = 80,
    this.shopBio,
    this.followerCount = 0,
    this.followingCount = 0,
    this.createdAt,
    this.email,
    this.phone,
  });

  factory SellerProfile.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? userRow,
    int? activeProductCount,
    int? totalProductCount,
  }) {
    final user =
        (userRow ?? row['user'] ?? row['user_public_profiles'] ?? row['users'])
            as Map<String, dynamic>?;

    final sellerId =
        row['seller_id'] as String? ??
        user?['user_id'] as String? ??
        row['user_id'] as String?;

    final username =
        user?['username'] as String? ?? (row['username'] as String? ?? '');

    final ownerName =
        user?['full_name'] as String? ??
        (row['full_name'] as String? ??
            (username.isNotEmpty ? username : 'Seller'));

    final avatarUrl =
        user?['avatar'] as String? ??
        (row['avatar'] as String? ??
            'https://ui-avatars.com/api/?name=${Uri.encodeComponent(ownerName)}&background=0D9488&color=fff&size=150');

    final bannerUrl =
        row['banner_url'] as String? ?? row['cover_image'] as String?;

    final rating =
        (user?['rating_average'] as num?)?.toDouble() ??
        (row['rating_average'] as num?)?.toDouble() ??
        (row['rating'] as num?)?.toDouble() ??
        0;

    final ratingCount =
        (user?['rating_count'] as num?)?.toInt() ??
        (row['rating_count'] as num?)?.toInt() ??
        0;

    final rawShopName = row['shop_name'] as String?;
    final shopName = (rawShopName != null && rawShopName.trim().isNotEmpty)
        ? rawShopName.trim()
        : (ownerName.isNotEmpty ? ownerName : username);

    final sales = (row['total_sales'] as num?)?.toInt() ?? 0;
    final followerCount = (row['follower_count'] as num?)?.toInt() ?? 0;
    final followingCount = (row['following_count'] as num?)?.toInt() ?? 0;
    final trustScore = (user?['trust_score'] as num?)?.toInt() ?? 80;
    final shopBio =
        row['shop_bio'] as String? ??
        user?['bio'] as String? ??
        row['bio'] as String?;
    final city =
        row['city'] as String? ??
        row['barangay'] as String? ??
        user?['location'] as String? ??
        '';
    final isApproved =
        (row['is_approved'] as bool?) ?? (user?['role'] == 'seller');

    final createdAt = row['created_at'] != null
        ? DateTime.tryParse(row['created_at'] as String)
        : (user?['created_at'] != null
              ? DateTime.tryParse(user!['created_at'] as String)
              : null);

    return SellerProfile(
      sellerId: sellerId,
      username: username,
      shopName: shopName,
      ownerName: ownerName,
      avatarUrl: avatarUrl,
      bannerUrl: bannerUrl,
      rating: rating,
      ratingCount: ratingCount,
      sales: sales,
      itemCount: activeProductCount ?? totalProductCount ?? 0,
      distanceKm: 0.0,
      isVerified: isApproved,
      location: city.isNotEmpty ? city : 'Davao City',
      trustScore: trustScore,
      shopBio: shopBio,
      followerCount: followerCount,
      followingCount: followingCount,
      createdAt: createdAt,
      email: user?['email'] as String?,
      phone: user?['phone_number'] as String?,
    );
  }

  final String? sellerId;
  final String username;
  final String shopName;
  final String ownerName;
  final String avatarUrl;
  final String? bannerUrl;
  final double rating;
  final int ratingCount;
  final int sales;
  final int itemCount;
  final double distanceKm;
  final bool isVerified;
  final String location;
  final int trustScore;
  final String? shopBio;
  final int followerCount;
  final int followingCount;
  final DateTime? createdAt;
  final String? email;
  final String? phone;

  SellerProfile copyWith({
    String? sellerId,
    String? username,
    String? shopName,
    String? ownerName,
    String? avatarUrl,
    String? bannerUrl,
    double? rating,
    int? ratingCount,
    int? sales,
    int? itemCount,
    double? distanceKm,
    bool? isVerified,
    String? location,
    int? trustScore,
    String? shopBio,
    int? followerCount,
    int? followingCount,
    DateTime? createdAt,
    String? email,
    String? phone,
  }) => SellerProfile(
    sellerId: sellerId ?? this.sellerId,
    username: username ?? this.username,
    shopName: shopName ?? this.shopName,
    ownerName: ownerName ?? this.ownerName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bannerUrl: bannerUrl ?? this.bannerUrl,
    rating: rating ?? this.rating,
    ratingCount: ratingCount ?? this.ratingCount,
    sales: sales ?? this.sales,
    itemCount: itemCount ?? this.itemCount,
    distanceKm: distanceKm ?? this.distanceKm,
    isVerified: isVerified ?? this.isVerified,
    location: location ?? this.location,
    trustScore: trustScore ?? this.trustScore,
    shopBio: shopBio ?? this.shopBio,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
    createdAt: createdAt ?? this.createdAt,
    email: email ?? this.email,
    phone: phone ?? this.phone,
  );

  Map<String, dynamic> toJson() => {
    'seller_id': sellerId,
    'username': username,
    'shop_name': shopName,
    'owner_name': ownerName,
    'avatar_url': avatarUrl,
    'banner_url': bannerUrl,
    'rating': rating,
    'rating_count': ratingCount,
    'sales': sales,
    'item_count': itemCount,
    'distance_km': distanceKm,
    'is_verified': isVerified,
    'location': location,
    'trust_score': trustScore,
    'shop_bio': shopBio,
    'follower_count': followerCount,
    'following_count': followingCount,
    'created_at': createdAt?.toIso8601String(),
    'email': email,
    'phone': phone,
  };
}
