import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class SellerApplication {
  const SellerApplication({
    required this.id,
    required this.userId,
    required this.shopName,
    required this.shopAddress,
    required this.barangay,
    required this.city,
    required this.status,
    required this.submittedAt,
    required this.livenessPassed,
    required this.livenessResult,
    this.idPath,
    this.idBackPath,
    this.idType,
    this.selfiePath,
    this.applicantName,
    this.applicantEmail,
    this.applicantUsername,
    this.rejectionReason,
    this.claimedSellingRange,
    this.reviewedAt,
  });

  final String id;
  final String userId;
  final String shopName;
  final String shopAddress;
  final String barangay;
  final String city;
  final String status;
  final DateTime submittedAt;
  final bool livenessPassed;
  final Map<String, dynamic> livenessResult;
  final String? idPath;
  final String? idBackPath;
  final String? idType;
  final String? selfiePath;
  final String? applicantName;
  final String? applicantEmail;
  final String? applicantUsername;
  final String? rejectionReason;
  final String? claimedSellingRange;
  final DateTime? reviewedAt;

  factory SellerApplication.fromJson(Map<String, dynamic> json) {
    final user = json['users'];
    return SellerApplication(
      id: json['verification_id'] as String,
      userId: json['user_id'] as String,
      shopName: json['shop_name'] as String? ?? 'Shop',
      shopAddress: json['shop_address'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      city: json['city'] as String? ?? 'Davao City',
      status: json['verification_status'] as String? ?? 'pending',
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : DateTime.now(),
      livenessPassed: json['liveness_passed'] as bool? ?? false,
      livenessResult: Map<String, dynamic>.from(
        json['liveness_result'] as Map? ?? const {},
      ),
      idPath: json['government_id_front'] as String?,
      idBackPath: json['government_id_back'] as String?,
      idType: json['government_id_type'] as String?,
      selfiePath: json['selfie_image'] as String?,
      applicantName: user is Map ? user['full_name'] as String? : null,
      applicantEmail: user is Map ? user['email'] as String? : null,
      applicantUsername: user is Map ? user['username'] as String? : null,
      rejectionReason: json['rejection_reason'] as String?,
      claimedSellingRange: json['claimed_selling_range'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
    );
  }

  SellerApplication withApplicantName(String? name) {
    return withApplicantProfile(name: name);
  }

  SellerApplication withApplicantProfile({
    String? name,
    String? email,
    String? username,
  }) {
    return SellerApplication(
      id: id,
      userId: userId,
      shopName: shopName,
      shopAddress: shopAddress,
      barangay: barangay,
      city: city,
      status: status,
      submittedAt: submittedAt,
      livenessPassed: livenessPassed,
      livenessResult: livenessResult,
      idPath: idPath,
      idBackPath: idBackPath,
      idType: idType,
      selfiePath: selfiePath,
      applicantName: (name != null && name.trim().isNotEmpty)
          ? name
          : applicantName,
      applicantEmail: (email != null && email.trim().isNotEmpty)
          ? email
          : applicantEmail,
      applicantUsername: (username != null && username.trim().isNotEmpty)
          ? username
          : applicantUsername,
      rejectionReason: rejectionReason,
      claimedSellingRange: claimedSellingRange,
      reviewedAt: reviewedAt,
    );
  }
}

class AdminVerificationService {
  AdminVerificationService(this._supabase);

  final SupabaseService _supabase;

  Future<SellerApplication?> getById(String verificationId) async {
    final row = await _supabase.client
        .from('user_verifications')
        .select()
        .eq('verification_id', verificationId)
        .maybeSingle();
    if (row == null) return null;
    var application = SellerApplication.fromJson(row);
    try {
      final profile = await _supabase.client
          .from('user_public_profiles')
          .select('full_name, username')
          .eq('user_id', application.userId)
          .maybeSingle();
      if (profile != null) {
        application = application.withApplicantProfile(
          name: profile['full_name'] as String?,
          username: profile['username'] as String?,
        );
      }
    } catch (_) {}
    return application;
  }

  Future<List<SellerApplication>> listPending() {
    return listByStatus('pending');
  }

  Future<List<SellerApplication>> listByStatus(String status) async {
    final res = await listPaged(page: 0, pageSize: 100, status: status);
    return res.items;
  }

  /// Server-side filtered and paginated seller verification query.
  Future<({List<SellerApplication> items, int total})> listPaged({
    required int page,
    required int pageSize,
    String status = 'all',
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    try {
      return await _listPagedWithProfileJoin(
        page: page,
        pageSize: pageSize,
        status: status,
        search: search,
        from: from,
        toExclusive: toExclusive,
      );
    } catch (e, st) {
      debugPrint(
        'AdminVerificationService.listPaged embed query failed: $e\n$st',
      );
      return _listPagedWithUserLookup(
        page: page,
        pageSize: pageSize,
        status: status,
        search: search,
        from: from,
        toExclusive: toExclusive,
      );
    }
  }

  Future<({List<SellerApplication> items, int total})>
  _listPagedWithProfileJoin({
    required int page,
    required int pageSize,
    String status = 'all',
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    final fromIndex = page * pageSize;
    final toIndex = fromIndex + pageSize - 1;

    var query = _applyVerificationFilters(
      _supabase.client
          .from('user_verifications')
          .select('*, users(full_name, email, username)'),
      status: status,
      search: search,
      from: from,
      toExclusive: toExclusive,
      searchOnUsersJoin: true,
    );

    final response = await query
        .order('submitted_at', ascending: false)
        .order('verification_id', ascending: false)
        .range(fromIndex, toIndex)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    final applications = data
        .map(
          (row) =>
              SellerApplication.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();

    return (items: applications, total: response.count);
  }

  Future<({List<SellerApplication> items, int total})>
  _listPagedWithUserLookup({
    required int page,
    required int pageSize,
    String status = 'all',
    String? search,
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    final fromIndex = page * pageSize;
    final toIndex = fromIndex + pageSize - 1;

    var query = _applyVerificationFilters(
      _supabase.client.from('user_verifications').select(),
      status: status,
      search: null,
      from: from,
      toExclusive: toExclusive,
      searchOnUsersJoin: false,
    );

    final trimmedSearch = search?.trim();
    if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
      final term = _escapeIlikePattern(trimmedSearch);
      final userIds = await _matchingUserIds(term);
      if (userIds.isEmpty) {
        query = query.ilike('shop_name', '%$term%');
      } else {
        query = query.or(
          'shop_name.ilike.%$term%,user_id.in.(${userIds.join(',')})',
        );
      }
    }

    final response = await query
        .order('submitted_at', ascending: false)
        .order('verification_id', ascending: false)
        .range(fromIndex, toIndex)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    var applications = data
        .map(
          (row) =>
              SellerApplication.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();

    if (applications.isEmpty) {
      return (items: applications, total: response.count);
    }

    final userIds = applications.map((app) => app.userId).toSet().toList();
    try {
      final profiles = await _supabase.client
          .from('users')
          .select('user_id, full_name, email, username')
          .inFilter('user_id', userIds);

      final profileMap =
          <String, ({String name, String email, String username})>{
            for (final row in profiles as List)
              (row as Map)['user_id'] as String: (
                name: (row['full_name'] as String?) ?? '',
                email: (row['email'] as String?) ?? '',
                username: (row['username'] as String?) ?? '',
              ),
          };

      applications = applications.map((app) {
        final p = profileMap[app.userId];
        if (p != null) {
          return app.withApplicantProfile(
            name: p.name,
            email: p.email,
            username: p.username,
          );
        }
        return app;
      }).toList();
    } catch (_) {}

    return (items: applications, total: response.count);
  }

  PostgrestFilterBuilder<PostgrestList> _applyVerificationFilters(
    PostgrestFilterBuilder<PostgrestList> query, {
    required String status,
    required String? search,
    required DateTime? from,
    required DateTime? toExclusive,
    required bool searchOnUsersJoin,
  }) {
    if (status != 'all' && status.isNotEmpty) {
      query = query.eq('verification_status', status);
    }
    if (from != null) {
      query = query.gte('submitted_at', from.toUtc().toIso8601String());
    }
    if (toExclusive != null) {
      query = query.lt('submitted_at', toExclusive.toUtc().toIso8601String());
    }

    if (searchOnUsersJoin) {
      final trimmedSearch = search?.trim();
      if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
        final term = _escapeIlikePattern(trimmedSearch);
        query = query.or(
          'shop_name.ilike.%$term%,'
          'users.full_name.ilike.%$term%,'
          'users.email.ilike.%$term%,'
          'users.username.ilike.%$term%',
        );
      }
    }
    return query;
  }

  Future<List<String>> _matchingUserIds(String term) async {
    try {
      final rows = await _supabase.client
          .from('users')
          .select('user_id')
          .or(
            'full_name.ilike.%$term%,email.ilike.%$term%,username.ilike.%$term%',
          )
          .limit(100);
      return [
        for (final row in rows as List)
          if (row is Map && row['user_id'] is String) row['user_id'] as String,
      ];
    } catch (e) {
      debugPrint('AdminVerificationService user search fallback: $e');
      return const [];
    }
  }

  static String _escapeIlikePattern(String raw) {
    return raw
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Returns the count of verifications grouped by status.
  Future<({int pending, int approved, int rejected, int total})>
  countAll() async {
    final rows = await _supabase.client
        .from('user_verifications')
        .select('verification_status');
    int pending = 0, approved = 0, rejected = 0;
    for (final row in (rows as List)) {
      switch ((row as Map)['verification_status'] as String?) {
        case 'pending':
          pending++;
        case 'approved':
          approved++;
        case 'rejected':
          rejected++;
      }
    }
    return (
      pending: pending,
      approved: approved,
      rejected: rejected,
      total: rows.length,
    );
  }

  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final signed = await _supabase.client.storage
        .from('verification-docs')
        .createSignedUrl(path, 60 * 10);
    return signed;
  }

  Future<void> review({
    required String verificationId,
    required String decision,
    String? reason,
  }) async {
    await _supabase.client.rpc(
      'review_seller_verification',
      params: {
        'p_verification_id': verificationId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }
}
