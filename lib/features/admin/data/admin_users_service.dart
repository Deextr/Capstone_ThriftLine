import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../domain/marketplace_user_management.dart';

class MarketplaceUserCounts {
  const MarketplaceUserCounts({
    required this.total,
    required this.active,
    required this.disabled,
    required this.banned,
  });

  final int total;
  final int active;
  final int disabled;
  final int banned;

  static const empty = MarketplaceUserCounts(
    total: 0,
    active: 0,
    disabled: 0,
    banned: 0,
  );

  factory MarketplaceUserCounts.fromJson(Map<String, dynamic>? json) {
    int read(String key) {
      final value = json?[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return MarketplaceUserCounts(
      total: read('total'),
      active: read('active'),
      disabled: read('disabled'),
      banned: read('banned'),
    );
  }
}

class MarketplaceUserRow {
  const MarketplaceUserRow({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.username,
    required this.role,
    required this.accountStatus,
    required this.accountType,
    required this.createdAt,
    required this.sellerApproved,
    this.shopName,
    this.verificationStatus,
    this.canDisable = false,
    this.sanctionReason,
    this.permanentlyDisabledAt,
    this.restrictedUntil,
    this.strikeCount,
    this.adminDisableReason,
    this.adminDisableNotes,
    this.adminDisabledAt,
    this.trustLevel,
    this.trustScore,
    this.displayAccountStatus,
  });

  final String userId;
  final String fullName;
  final String email;
  final String username;
  final String role;
  final String accountStatus;
  final String accountType;
  final DateTime createdAt;
  final bool sellerApproved;
  final String? shopName;
  final String? verificationStatus;
  final bool canDisable;
  final String? sanctionReason;
  final DateTime? permanentlyDisabledAt;
  final DateTime? restrictedUntil;
  final int? strikeCount;
  final String? adminDisableReason;
  final String? adminDisableNotes;
  final DateTime? adminDisabledAt;
  final String? trustLevel;
  final int? trustScore;
  final String? displayAccountStatus;

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return email.trim().isEmpty ? 'Marketplace user' : email.trim();
  }

  String get accountTypeLabel => marketplaceAccountTypeLabel(accountType);

  String get effectiveAccountStatus =>
      displayAccountStatus ??
      marketplaceEffectiveAccountStatus(
        accountStatus: accountStatus,
        trustLevel: trustLevel,
      );

  String get statusLabel =>
      marketplaceAccountStatusLabel(effectiveAccountStatus);

  bool get mayDisable => canDisableMarketplaceAccount(
    role: role,
    accountStatus: accountStatus,
    trustLevel: trustLevel,
  );

  String? get disableBlockedMessage => marketplaceDisableBlockedMessage(
    role: role,
    accountStatus: accountStatus,
    trustLevel: trustLevel,
  );

  factory MarketplaceUserRow.fromJson(Map<String, dynamic> json) {
    final status = (json['account_status'] as String?)?.trim() ?? 'active';
    final role = (json['role'] as String?)?.trim() ?? 'buyer';
    final trustLevel = _nullableText(json['trust_level']);
    final trustScoreRaw = json['trust_score'];
    final serverCanDisable = json['can_disable'] == true;
    final displayStatus = _nullableText(json['display_account_status']);
    return MarketplaceUserRow(
      userId: json['user_id']?.toString() ?? '',
      fullName: (json['full_name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim() ?? '',
      role: role,
      accountStatus: status,
      accountType: (json['account_type'] as String?)?.trim() ?? 'buyer',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sellerApproved: json['seller_approved'] == true,
      shopName: _nullableText(json['shop_name']),
      verificationStatus: _nullableText(json['verification_status']),
      canDisable:
          serverCanDisable &&
          canDisableMarketplaceAccount(
            role: role,
            accountStatus: status,
            trustLevel: trustLevel,
          ),
      trustLevel: trustLevel,
      trustScore: trustScoreRaw is num ? trustScoreRaw.toInt() : null,
      displayAccountStatus: displayStatus,
      sanctionReason: _nullableText(json['sanction_reason']),
      permanentlyDisabledAt: _time(json['permanently_disabled_at']),
      restrictedUntil: _time(json['restricted_until']),
      strikeCount: (json['strike_count'] as num?)?.toInt(),
      adminDisableReason: _nullableText(json['admin_disable_reason']),
      adminDisableNotes: _nullableText(json['admin_disable_notes']),
      adminDisabledAt: _time(json['admin_disabled_at']),
    );
  }
}

class MarketplaceUsersPage {
  const MarketplaceUsersPage({
    required this.rows,
    required this.total,
    required this.counts,
  });

  final List<MarketplaceUserRow> rows;
  final int total;
  final MarketplaceUserCounts counts;
}

class MarketplaceDisableResult {
  const MarketplaceDisableResult({required this.ok, this.code, this.message});

  final bool ok;
  final String? code;
  final String? message;
}

class AdminUsersService {
  AdminUsersService(this._supabase);

  final SupabaseService _supabase;

  Future<MarketplaceUsersPage> list({
    required int page,
    required int pageSize,
    String? search,
    String? accountType,
    String? status,
  }) async {
    final raw = await _supabase.client.rpc(
      'list_marketplace_users',
      params: {
        'p_search': search?.trim() ?? '',
        'p_account_type': accountType,
        'p_status': status,
        'p_limit': pageSize,
        'p_offset': page * pageSize,
      },
    );
    final map = supabaseRpcMap(raw) ?? const <String, dynamic>{};
    final rowsRaw = map['rows'];
    final rows = <MarketplaceUserRow>[
      if (rowsRaw is List)
        for (final row in rowsRaw)
          if (row is Map)
            MarketplaceUserRow.fromJson(Map<String, dynamic>.from(row)),
    ];
    final total = map['total'];
    return MarketplaceUsersPage(
      rows: rows,
      total: total is num
          ? total.toInt()
          : int.tryParse(total?.toString() ?? '') ?? rows.length,
      counts: MarketplaceUserCounts.fromJson(supabaseRpcMap(map['counts'])),
    );
  }

  Future<MarketplaceUserRow?> detail(String userId) async {
    final raw = await _supabase.client.rpc(
      'get_marketplace_user',
      params: {'p_user_id': userId},
    );
    final map = supabaseRpcMap(raw);
    if (map == null || map['success'] != true) return null;
    final user = supabaseRpcMap(map['user']);
    if (user == null) return null;
    return MarketplaceUserRow.fromJson(user);
  }

  Future<MarketplaceDisableResult> disable({
    required String userId,
    required String reason,
    required String notes,
  }) async {
    if (!marketplaceDisableReasonAllowed(reason)) {
      return const MarketplaceDisableResult(
        ok: false,
        code: 'invalid_reason',
        message: 'Choose a reason for disabling this account.',
      );
    }
    try {
      final raw = await _supabase.client.rpc(
        'disable_marketplace_account',
        params: {
          'p_user_id': userId,
          'p_reason': reason.trim(),
          'p_notes': notes.trim(),
        },
      );
      final map = supabaseRpcMap(raw);
      if (map?['success'] == true) {
        return const MarketplaceDisableResult(ok: true);
      }
      return MarketplaceDisableResult(
        ok: false,
        code: map?['code']?.toString(),
        message: _disableMessage(
          map?['code']?.toString(),
          map?['error']?.toString(),
        ),
      );
    } on PostgrestException catch (e) {
      debugPrint('disable_marketplace_account error: ${e.message}');
      final text = e.message.toLowerCase();
      if (text.contains('admin access')) {
        return const MarketplaceDisableResult(
          ok: false,
          code: 'unauthorized',
          message: 'You do not have permission to manage marketplace accounts.',
        );
      }
      return const MarketplaceDisableResult(
        ok: false,
        message: 'Could not disable this account. Nothing was changed.',
      );
    } catch (e) {
      debugPrint('disable_marketplace_account error: $e');
      return const MarketplaceDisableResult(
        ok: false,
        message: 'Could not disable this account. Nothing was changed.',
      );
    }
  }
}

String _disableMessage(String? code, String? serverMessage) {
  switch (code) {
    case 'already_disabled':
      return 'Account already disabled. No further disabling action is available.';
    case 'already_banned':
      return 'Account banned. This account is already restricted.';
    case 'already_restricted':
      return 'This account is already restricted.';
    case 'not_marketplace_account':
      return 'Administrator accounts are managed separately.';
    case 'invalid_reason':
      return 'Choose a reason for disabling this account.';
    case 'notes_too_long':
      return 'Keep additional notes under 1,000 characters.';
    case 'not_found':
      return 'That account was not found.';
    case 'unauthorized':
      return 'You do not have permission to manage marketplace accounts.';
    default:
      final text = serverMessage?.trim() ?? '';
      if (text.isEmpty) {
        return 'Could not disable this account. Nothing was changed.';
      }
      return text;
  }
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

DateTime? _time(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
