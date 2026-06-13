import '../../../models/enums.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.location,
    this.shopName,
    this.rating,
    this.sales,
    this.isVerified = false,
  });

  final String id;
  final String username;
  final String name;
  final UserRole role;
  final String avatarUrl;
  final String location;
  final String? shopName;
  final double? rating;
  final int? sales;
  final bool isVerified;

  String get displayName => role == UserRole.seller ? (shopName ?? name) : name;
  bool get isBuyer => role == UserRole.buyer;
  bool get isSeller => role == UserRole.seller;
}
