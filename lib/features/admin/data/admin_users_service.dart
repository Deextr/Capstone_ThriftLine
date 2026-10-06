import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';

class AdminUserRow {
  const AdminUserRow({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.username,
    required this.role,
    required this.accountStatus,
    required this.trustScore,
    required this.rating,
    required this.createdAt,
    this.lastActiveAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final String username;
  final UserRole role;
  final String accountStatus;
  final double trustScore;
  final double rating;
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  factory AdminUserRow.fromJson(Map<String, dynamic> json) {
    return AdminUserRow(
      userId: json['user_id'] as String,
      fullName: (json['full_name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim() ?? '',
      role: UserRole.fromString(json['role'] as String? ?? 'buyer'),
      accountStatus: (json['account_status'] as String?)?.trim() ?? 'active',
      trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.tryParse(json['last_active_at'] as String)
          : null,
    );
  }
}

class AdminUsersPage {
  const AdminUsersPage({required this.rows, required this.total});

  final List<AdminUserRow> rows;
  final int total;
}

class AdminUsersService {
  AdminUsersService(this._supabase);

  final SupabaseService _supabase;

  Future<AdminUsersPage> list({
    required int page,
    required int pageSize,
    String? search,
    String? roleFilter,
    String? statusFilter,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    var filter = _supabase.client.from('users').select(
      'user_id, full_name, email, username, role, account_status, '
      'trust_score, rating, created_at, last_active_at',
    );

    if (roleFilter != null && roleFilter.isNotEmpty) {
      filter = filter.eq('role', roleFilter);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      filter = filter.eq('account_status', statusFilter);
    }
    if (search != null && search.trim().isNotEmpty) {
      final term = search.trim();
      filter = filter.or(
        'full_name.ilike.%$term%,email.ilike.%$term%,username.ilike.%$term%',
      );
    }

    final response = await filter
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final data = response.data as List? ?? const [];
    final rows = data
        .map((row) => AdminUserRow.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    return AdminUsersPage(rows: rows, total: response.count);
  }
}
