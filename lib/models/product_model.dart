import 'enums.dart';

class BidEntry {
  const BidEntry({
    required this.id,
    required this.username,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String username;
  final double amount;
  final DateTime createdAt;
}

class ProductModel {
  const ProductModel({
    required this.id,
    this.sellerId,
    this.categoryId,
    required this.sellerUsername,
    required this.sellerName,
    required this.sellerAvatar,
    required this.sellerVerified,
    required this.title,
    required this.description,
    required this.price,
    required this.category,
    required this.condition,
    this.imageUrls = const [],
    this.status = ProductStatus.active,
    this.size,
    this.brand,
    this.color,
    this.material,
    this.location,
    required this.createdAt,
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.sellingType = SellingType.fixedPrice,
    this.currentBid,
    this.startingBid,
    this.bidIncrement = 20,
    this.bidEndTime,
    this.bidCount = 0,
    this.bidHistory = const [],
    this.buyNowEnabled = false,
    this.distanceKm,
    this.likesCount = 0,
  });

  /// Constructs a [ProductModel] from a Supabase `products` row that has been
  /// selected with the following joins:
  ///
  /// ```sql
  /// products (
  ///   *,
  ///   seller:users!products_seller_id_fkey (user_id, username, full_name, avatar, ...),
  ///   images:product_images (image_url, is_primary, display_order),
  ///   category:categories (category_name)
  /// )
  /// ```
  factory ProductModel.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? sellerProfile,
  }) {
    // â”€â”€ Seller info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final seller = (row['seller'] ??
            row['user_public_profiles'] ??
            row['users'])
        as Map<String, dynamic>?;

    final sellerUsername = seller?['username'] as String? ?? '';
    final sellerFullName = seller?['full_name'] as String? ?? '';

    // Shop name from seller_profiles if available, otherwise full_name or username
    final rawShopName = sellerProfile?['shop_name'] as String?;
    final shopName = (rawShopName != null && rawShopName.trim().isNotEmpty)
        ? rawShopName.trim()
        : (sellerFullName.trim().isNotEmpty
            ? sellerFullName.trim()
            : (sellerUsername.trim().isNotEmpty
                ? sellerUsername.trim()
                : 'Thrift Seller'));

    final sellerAvatar = seller?['avatar'] as String? ?? '';
    final isApproved = (sellerProfile?['is_approved'] as bool?) ?? false;
    final isSellerRole = seller?['role'] == 'seller';
    final ratingAvg = (seller?['rating_average'] as num?)?.toDouble() ?? 0.0;
    final sellerVerified = isApproved || isSellerRole || ratingAvg > 0;

    // â”€â”€ Images â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final rawImages = row['images'] as List<dynamic>? ?? [];
    final sortedImages =
        List<Map<String, dynamic>>.from(
          rawImages.map((e) => e as Map<String, dynamic>),
        )..sort((a, b) {
          // Primary images first, then by display_order
          final aPrimary = a['is_primary'] as bool? ?? false;
          final bPrimary = b['is_primary'] as bool? ?? false;
          if (aPrimary != bPrimary) return aPrimary ? -1 : 1;
          return (a['display_order'] as int? ?? 0).compareTo(
            b['display_order'] as int? ?? 0,
          );
        });
    final imageUrls = sortedImages
        .map((img) => img['image_url'] as String)
        .toList();

    // â”€â”€ Category â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final categoryRow = row['category'] as Map<String, dynamic>?;
    final categoryName = categoryRow?['category_name'] as String? ?? '';
    final category = ProductCategory.fromString(categoryName);

    // â”€â”€ Auction data (from joined auctions or fallback) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final auctionsRaw = row['auctions'];
    Map<String, dynamic>? activeAuction;
    if (auctionsRaw is List && auctionsRaw.isNotEmpty) {
      final activeList = auctionsRaw
          .where((a) => (a as Map<String, dynamic>)['status'] == 'active')
          .toList();
      activeAuction = (activeList.isNotEmpty ? activeList.first : auctionsRaw.first)
          as Map<String, dynamic>?;
    } else if (auctionsRaw is Map<String, dynamic>) {
      activeAuction = auctionsRaw;
    }

    final sellingType = SellingType.fromDbString(
      row['listing_type'] as String? ?? 'fixed_price',
    );

    double? startingBid;
    double? currentBid;
    double bidIncrement = 20;
    DateTime? bidEndTime;

    if (activeAuction != null) {
      startingBid = (activeAuction['starting_price'] as num?)?.toDouble();
      currentBid =
          (activeAuction['current_price'] as num?)?.toDouble() ?? startingBid;
      bidIncrement =
          (activeAuction['minimum_increment'] as num?)?.toDouble() ?? 20;
      if (activeAuction['ends_at'] != null) {
        bidEndTime = DateTime.tryParse(activeAuction['ends_at'] as String);
      }
    }

    if (sellingType == SellingType.auction) {
      final priceVal = (row['price'] as num?)?.toDouble() ?? 0;
      startingBid ??= priceVal > 0 ? priceVal : 100;
      currentBid ??= startingBid;
      if (bidEndTime == null || !bidEndTime.isAfter(DateTime.now())) {
        final createdAt = row['created_at'] != null
            ? DateTime.tryParse(row['created_at'] as String) ?? DateTime.now()
            : DateTime.now();
        final defaultEnd = createdAt.add(const Duration(days: 3));
        bidEndTime = defaultEnd.isAfter(DateTime.now())
            ? defaultEnd
            : DateTime.now().add(const Duration(days: 2));
      }
    }

    // â”€â”€ Core fields â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    return ProductModel(
      id: row['product_id'] as String? ?? '',
      sellerId: row['seller_id'] as String?,
      categoryId: row['category_id'] as String?,
      sellerUsername: sellerUsername,
      sellerName: shopName,
      sellerAvatar: sellerAvatar,
      sellerVerified: sellerVerified,
      title: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      price: (row['price'] as num?)?.toDouble() ?? 0,
      category: category,
      condition: ProductCondition.fromDbString(
        row['condition'] as String? ?? 'good',
      ),
      imageUrls: imageUrls,
      status: ProductStatus.fromDbString(row['status'] as String? ?? 'active'),
      size: row['size'] as String?,
      brand: row['brand'] as String?,
      color: row['color'] as String?,
      location: row['location'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      viewCount: row['views'] as int? ?? 0,
      favoriteCount: row['favorite_count'] as int? ?? 0,
      sellingType: sellingType,
      startingBid: startingBid,
      currentBid: currentBid,
      bidIncrement: bidIncrement,
      bidEndTime: bidEndTime,
    );
  }

  final String id;
  final String? sellerId;
  final String? categoryId;

  final String sellerUsername;
  final String sellerName;
  final String sellerAvatar;
  final bool sellerVerified;
  final String title;
  final String description;
  final double price;
  final ProductCategory category;
  final ProductCondition condition;
  final List<String> imageUrls;
  final ProductStatus status;
  final String? size;
  final String? brand;
  final String? color;
  final String? material;
  final String? location;
  final DateTime createdAt;
  final int viewCount;
  final int favoriteCount;
  final SellingType sellingType;
  final double? currentBid;
  final double? startingBid;
  final double bidIncrement;
  final DateTime? bidEndTime;
  final int bidCount;
  final List<BidEntry> bidHistory;
  final bool buyNowEnabled;
  final double? distanceKm;
  final int likesCount;

  bool get hasActiveBid =>
      sellingType != SellingType.fixedPrice &&
      bidEndTime != null &&
      bidEndTime!.isAfter(DateTime.now());

  String get imageUrl => imageUrls.isNotEmpty
      ? imageUrls.first
      : 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&q=80&w=600&h=600';

  double get displayPrice =>
      hasActiveBid ? (currentBid ?? startingBid ?? price) : price;

  ProductModel copyWith({
    String? id,
    String? sellerId,
    String? categoryId,
    String? sellerUsername,
    String? sellerName,
    String? sellerAvatar,
    bool? sellerVerified,
    String? title,
    String? description,
    double? price,
    ProductCategory? category,
    ProductCondition? condition,
    List<String>? imageUrls,
    ProductStatus? status,
    String? size,
    String? brand,
    String? color,
    String? material,
    String? location,
    DateTime? createdAt,
    int? viewCount,
    int? favoriteCount,
    SellingType? sellingType,
    double? currentBid,
    double? startingBid,
    double? bidIncrement,
    DateTime? bidEndTime,
    int? bidCount,
    List<BidEntry>? bidHistory,
    bool? buyNowEnabled,
    double? distanceKm,
    int? likesCount,
  }) => ProductModel(
    id: id ?? this.id,
    sellerId: sellerId ?? this.sellerId,
    categoryId: categoryId ?? this.categoryId,
    sellerUsername: sellerUsername ?? this.sellerUsername,
    sellerName: sellerName ?? this.sellerName,
    sellerAvatar: sellerAvatar ?? this.sellerAvatar,
    sellerVerified: sellerVerified ?? this.sellerVerified,
    title: title ?? this.title,
    description: description ?? this.description,
    price: price ?? this.price,
    category: category ?? this.category,
    condition: condition ?? this.condition,
    imageUrls: imageUrls ?? this.imageUrls,
    status: status ?? this.status,
    size: size ?? this.size,
    brand: brand ?? this.brand,
    color: color ?? this.color,
    material: material ?? this.material,
    location: location ?? this.location,
    createdAt: createdAt ?? this.createdAt,
    viewCount: viewCount ?? this.viewCount,
    favoriteCount: favoriteCount ?? this.favoriteCount,
    sellingType: sellingType ?? this.sellingType,
    currentBid: currentBid ?? this.currentBid,
    startingBid: startingBid ?? this.startingBid,
    bidIncrement: bidIncrement ?? this.bidIncrement,
    bidEndTime: bidEndTime ?? this.bidEndTime,
    bidCount: bidCount ?? this.bidCount,
    bidHistory: bidHistory ?? this.bidHistory,
    buyNowEnabled: buyNowEnabled ?? this.buyNowEnabled,
    distanceKm: distanceKm ?? this.distanceKm,
    likesCount: likesCount ?? this.likesCount,
  );
}
