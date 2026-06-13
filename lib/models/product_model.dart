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

  final String id;
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

  String get imageUrl =>
      imageUrls.isNotEmpty
          ? imageUrls.first
          : 'https://picsum.photos/seed/$id/400/400';

  double get displayPrice => hasActiveBid ? (currentBid ?? startingBid ?? price) : price;

  ProductModel copyWith({
    String? id,
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
  }) =>
      ProductModel(
        id: id ?? this.id,
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
