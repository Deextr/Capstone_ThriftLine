import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../core/utils/seller_trust.dart';
import '../../../models/enums.dart';
import 'trusted_device.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.avatarUrl,
    this.sellerAvatarUrl = '',
    required this.location,
    this.shopName,
    this.shopBio,
    this.rating,
    this.ratingCount = 0,
    this.sales,
    this.isVerified = false,
    this.bio,
    this.lastActive,
    this.verificationStatus = 'none',
    this.verificationRejectionReason,
    this.trustScore = 80,
    this.trustLevel,
    this.trustBreakdown,
    this.isPhoneVerified = false,
    this.usesEmailPasswordAuth = false,
    this.authIdentityProviders = const [],
    this.accountStatus = 'active',
  });

  final String id;
  final String username;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final String avatarUrl;
  final String sellerAvatarUrl;
  final String location;
  final String? shopName;
  final String? shopBio;
  final double? rating;
  final int ratingCount;
  final int? sales;
  final bool isVerified;
  final String? bio;
  final DateTime? lastActive;
  final String verificationStatus; // 'none', 'pending', 'approved', 'rejected'
  final String? verificationRejectionReason;
  final int trustScore;

  /// Table 17 class stored by the server. Null until the score has been written.
  final String? trustLevel;

  /// Criterion scores from `trust_breakdown`. Present on the signed-in user's row.
  final SellerTrustBreakdown? trustBreakdown;

  final bool isPhoneVerified;

  /// True when **this session** signed in with email/password.
  ///
  /// Trusted-device OTP and “forget this device” apply only then. Google
  /// Sign-In sessions stay false even if GoTrue also lists an `email`
  /// identity, and even if the address is Gmail. Buyer/Seller mode is
  /// unrelated.
  final bool usesEmailPasswordAuth;

  /// Providers from GoTrue identities at hydration (may include `google`
  /// even when the JWT session user omits the list).
  final List<String> authIdentityProviders;

  /// `users.account_status`. A banned account cannot keep using ThriftLine.
  final String accountStatus;

  bool get isPermanentlyDisabled => accountStatus == 'banned';

  String get displayName => role == UserRole.seller ? (shopName ?? name) : name;
  bool get isBuyer => role == UserRole.buyer;
  bool get isSeller => role == UserRole.seller;
  bool get isAdmin => role == UserRole.admin;

  /// Approved to use the seller workspace. The database role stays `seller`
  /// after admin approval; switching accounts never writes a second user row.
  bool get hasSellerAccess => isVerified || role == UserRole.seller;

  String get trustClassification =>
      resolveTrustLabel(score: trustScore, storedLevel: trustLevel);

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
    Iterable<String> sessionAmrMethods = const [],
  }) {
    final meta = supabaseUser.userMetadata ?? {};
    final status = verification?['verification_status'] as String? ?? 'none';
    final shopName =
        sellerProfile?['shop_name'] as String? ??
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
      phone:
          profile?['phone_number'] as String? ?? profile?['phone'] as String?,
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
      sellerAvatarUrl: sellerProfile?['shop_avatar_url'] as String? ?? '',
      location:
          profile?['location'] as String? ??
          [
            verification?['barangay'],
            verification?['city'] ?? sellerProfile?['city'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
      shopName: shopName,
      rating: (profile?['rating_average'] as num?)?.toDouble(),
      ratingCount: (profile?['rating_count'] as num?)?.toInt() ?? 0,
      sales: sellerProfile?['total_sales'] as int?,
      isVerified: approved,
      shopBio: sellerProfile?['shop_bio'] as String?,
      bio: profile?['bio'] as String?,
      lastActive: _parseTime(profile?['last_active_at']),
      verificationStatus: approved ? 'approved' : status,
      verificationRejectionReason: verification?['rejection_reason'] as String?,
      trustScore: (profile?['trust_score'] as num?)?.toInt() ?? 80,
      trustLevel: profile?['trust_level'] as String?,
      trustBreakdown: SellerTrustBreakdown.tryParse(
        profile?['trust_breakdown'],
      ),
      isPhoneVerified: profile?['is_phone_verified'] as bool? ?? false,
      authIdentityProviders: List<String>.unmodifiable(
        (supabaseUser.identities ?? []).map((i) => i.provider),
      ),
      accountStatus: profile?['account_status'] as String? ?? 'active',
      usesEmailPasswordAuth: authSessionUsesEmailPassword(
        lastAuthProvider: lastAuthProviderFromAppMetadata(
          supabaseUser.appMetadata,
        ),
        identityProviders:
            supabaseUser.identities?.map((i) => i.provider) ?? const <String>[],
        amrMethods: sessionAmrMethods,
      ),
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  AuthUser copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    String? avatarUrl,
    String? sellerAvatarUrl,
    String? location,
    String? shopName,
    String? shopBio,
    double? rating,
    int? ratingCount,
    int? sales,
    bool? isVerified,
    String? bio,
    DateTime? lastActive,
    String? verificationStatus,
    String? verificationRejectionReason,
    int? trustScore,
    String? trustLevel,
    SellerTrustBreakdown? trustBreakdown,
    bool? isPhoneVerified,
    bool? usesEmailPasswordAuth,
    List<String>? authIdentityProviders,
    String? accountStatus,
  }) {
    return AuthUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      sellerAvatarUrl: sellerAvatarUrl ?? this.sellerAvatarUrl,
      location: location ?? this.location,
      shopName: shopName ?? this.shopName,
      shopBio: shopBio ?? this.shopBio,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      sales: sales ?? this.sales,
      isVerified: isVerified ?? this.isVerified,
      bio: bio ?? this.bio,
      lastActive: lastActive ?? this.lastActive,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationRejectionReason:
          verificationRejectionReason ?? this.verificationRejectionReason,
      trustScore: trustScore ?? this.trustScore,
      trustLevel: trustLevel ?? this.trustLevel,
      trustBreakdown: trustBreakdown ?? this.trustBreakdown,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      usesEmailPasswordAuth:
          usesEmailPasswordAuth ?? this.usesEmailPasswordAuth,
      authIdentityProviders:
          authIdentityProviders ?? this.authIdentityProviders,
      accountStatus: accountStatus ?? this.accountStatus,
    );
  }
}
