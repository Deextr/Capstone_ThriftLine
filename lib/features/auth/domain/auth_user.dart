import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../models/enums.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    this.phone,
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
    this.isPhoneVerified = false,
  });

  final String id;
  final String username;
  final String name;
  final String email;
  final String? phone;
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
  final bool isPhoneVerified;

  String get displayName => role == UserRole.seller ? (shopName ?? name) : name;
  bool get isBuyer => role == UserRole.buyer;
  bool get isSeller => role == UserRole.seller;
  bool get isAdmin => role == UserRole.admin;

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

  /// Creates an [AuthUser] from a Supabase [User] and a `users` table row.
  ///
  /// The [profile] map may be `null` if the app-user row hasn't been created
  /// yet or if it is temporarily unavailable.
  factory AuthUser.fromSupabase(
    User supabaseUser,
    Map<String, dynamic>? profile, {
    Map<String, dynamic>? verification,
    Map<String, dynamic>? sellerProfile,
  }) {
    final meta = supabaseUser.userMetadata ?? {};
    final status = verification?['verification_status'] as String? ?? 'none';
    final shopName = sellerProfile?['shop_name'] as String? ??
        verification?['shop_name'] as String?;
    final approved = sellerProfile?['is_approved'] as bool? ?? false;

    return AuthUser(
      id: supabaseUser.id,
      username: profile?['username'] as String? ?? '',
      name:
          profile?['full_name'] as String? ??
          meta['full_name'] as String? ??
          meta['name'] as String? ??
          '',
      email: profile?['email'] as String? ?? supabaseUser.email ?? '',
      phone: profile?['phone_number'] as String? ?? profile?['phone'] as String?,
      role: UserRole.fromString(profile?['role'] as String? ?? 'buyer'),
      avatarUrl:
          profile?['avatar_url'] as String? ??
          profile?['avatar'] as String? ??
          profile?['avatarUrl'] as String? ??
          profile?['picture'] as String? ??
          meta['avatar_url'] as String? ??
          meta['picture'] as String? ??
          meta['avatar'] as String? ??
          '',
      location: profile?['location'] as String? ??
          [
            verification?['barangay'],
            verification?['city'] ?? sellerProfile?['city'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
      shopName: shopName,
      rating: (profile?['rating_average'] as num?)?.toDouble(),
      sales: sellerProfile?['total_sales'] as int?,
      isVerified: approved,
      bio: profile?['bio'] as String? ?? sellerProfile?['shop_bio'] as String?,
      verificationStatus: approved ? 'approved' : status,
      verificationRejectionReason: verification?['rejection_reason'] as String?,
      trustScore: (profile?['trust_score'] as num?)?.toInt() ?? 80,
      isPhoneVerified: profile?['is_phone_verified'] as bool? ?? false,
    );
  }

  AuthUser copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
    String? phone,
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
    bool? isPhoneVerified,
  }) {
    return AuthUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
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
      verificationRejectionReason:
          verificationRejectionReason ?? this.verificationRejectionReason,
      trustScore: trustScore ?? this.trustScore,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
    );
  }
}
