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
    this.bio,
    this.lastActive,
    this.verificationStatus = 'none',
    this.verificationRejectionReason,
    this.trustScore = 80,
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
  final String? bio;
  final DateTime? lastActive;
  final String verificationStatus; // 'none', 'pending', 'approved', 'rejected'
  final String? verificationRejectionReason;
  final int trustScore;

  String get displayName => role == UserRole.seller ? (shopName ?? name) : name;
  bool get isBuyer => role == UserRole.buyer;
  bool get isSeller => role == UserRole.seller;

  String get trustClassification {
    if (trustScore >= 90) return 'Highly Trusted Seller';
    if (trustScore >= 75) return 'Trusted Seller';
    if (trustScore >= 60) return 'Developing Seller';
    if (trustScore >= 40) return 'Under Review';
    return 'Banned';
  }

  String get lastActiveLabel {
    if (lastActive == null) return 'Offline';
    final diff = DateTime.now().difference(lastActive!);
    if (diff.inMinutes < 5) return 'Active now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    return 'Active ${diff.inDays}d ago';
  }

  AuthUser copyWith({
    String? id,
    String? username,
    String? name,
    UserRole? role,
    String? avatarUrl,
    String? location,
    String? shopName,
    double? rating,
    int? sales,
    bool? isVerified,
    String? bio,
    DateTime? lastActive,
    String? verificationStatus,
    String? verificationRejectionReason,
    int? trustScore,
  }) {
    return AuthUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      location: location ?? this.location,
      shopName: shopName ?? this.shopName,
      rating: rating ?? this.rating,
      sales: sales ?? this.sales,
      isVerified: isVerified ?? this.isVerified,
      bio: bio ?? this.bio,
      lastActive: lastActive ?? this.lastActive,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationRejectionReason: verificationRejectionReason ?? this.verificationRejectionReason,
      trustScore: trustScore ?? this.trustScore,
    );
  }
}
