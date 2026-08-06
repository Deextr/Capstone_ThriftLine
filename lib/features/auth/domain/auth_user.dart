import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../models/enums.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
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
  final String email;
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

  /// Creates an [AuthUser] from a Supabase [User] and a `profiles` table row.
  ///
  /// The [profile] map may be `null` if the profile hasn't been created yet
  /// (e.g. during a fresh Google sign-in before the trigger fires).
  factory AuthUser.fromSupabase(User supabaseUser, Map<String, dynamic>? profile) {
    final meta = supabaseUser.userMetadata ?? {};

    return AuthUser(
      id: supabaseUser.id,
      username: profile?['username'] as String? ?? '',
      name: profile?['name'] as String? ??
          meta['full_name'] as String? ??
          meta['name'] as String? ??
          '',
      email: supabaseUser.email ?? '',
      role: UserRole.fromString(profile?['role'] as String? ?? 'buyer'),
      avatarUrl: profile?['avatar_url'] as String? ??
          meta['avatar_url'] as String? ??
          '',
      location: profile?['location'] as String? ?? '',
      shopName: profile?['shop_name'] as String?,
      rating: (profile?['rating'] as num?)?.toDouble(),
      sales: profile?['sales'] as int?,
      isVerified: profile?['is_verified'] as bool? ?? false,
      bio: profile?['bio'] as String?,
      verificationStatus:
          profile?['verification_status'] as String? ?? 'none',
      verificationRejectionReason:
          profile?['verification_rejection_reason'] as String?,
      trustScore: profile?['trust_score'] as int? ?? 80,
    );
  }

  AuthUser copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
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
      email: email ?? this.email,
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
