class SellerProfile {
  const SellerProfile({
    required this.username,
    required this.shopName,
    required this.ownerName,
    required this.avatarUrl,
    required this.rating,
    required this.sales,
    required this.itemCount,
    required this.distanceKm,
    required this.isVerified,
    required this.location,
  });

  final String username;
  final String shopName;
  final String ownerName;
  final String avatarUrl;
  final double rating;
  final int sales;
  final int itemCount;
  final double distanceKm;
  final bool isVerified;
  final String location;
}
