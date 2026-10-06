import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import 'admin_audit_log_models.dart';
import 'admin_audit_service.dart';
import '../../buyer/domain/looking_for_lifecycle.dart';

class LookingForAdminReport {
  const LookingForAdminReport({
    required this.id,
    required this.postId,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    required this.postTitle,
    required this.postDescription,
    required this.postCreatedAt,
    required this.expiresAt,
    required this.postStatus,
    required this.reporterId,
    required this.reporterName,
    required this.reporterUsername,
    required this.reporterRole,
    required this.reportedUserId,
    required this.reportedName,
    required this.reportedUsername,
    required this.reportedRole,
    required this.reportedAccountStatus,
    required this.confirmedViolations,
    this.imageUrl,
    this.resolvedAt,
    this.moderationRemovedAt,
    this.ownerDeletedAt,
  });

  final String id;
  final String postId;
  final String reason;
  final String details;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String postTitle;
  final String postDescription;
  final String? imageUrl;
  final DateTime? postCreatedAt;
  final DateTime? expiresAt;
  final String postStatus;
  final DateTime? moderationRemovedAt;
  final DateTime? ownerDeletedAt;
  final String reporterId;
  final String reporterName;
  final String reporterUsername;
  final String reporterRole;
  final String reportedUserId;
  final String reportedName;
  final String reportedUsername;
  final String reportedRole;
  final String reportedAccountStatus;
  final int confirmedViolations;

  bool get canDecide => status == 'under_review';

  String lifecycleLabel(DateTime serverNow) {
    final life = classifyLookingFor(
      status: postStatus,
      expiresAt: expiresAt,
      serverNow: serverNow,
      moderationRemovedAt: moderationRemovedAt,
      ownerDeletedAt: ownerDeletedAt,
    );
    return lookingForLifecycleLabel(
      life,
      expiresAt: expiresAt,
      serverNow: serverNow,
    );
  }

  factory LookingForAdminReport.fromRow(Map<String, dynamic> row) {
    return LookingForAdminReport(
      id: row['report_id'] as String? ?? '',
      postId: row['post_id'] as String? ?? '',
      reason: row['reason'] as String? ?? '',
      details: row['details'] as String? ?? '',
      status: row['status'] as String? ?? 'under_review',
      createdAt: _time(row['created_at']) ?? DateTime.now().toUtc(),
      resolvedAt: _time(row['resolved_at']),
      postTitle: row['post_title'] as String? ?? '',
      postDescription: row['post_description'] as String? ?? '',
      imageUrl: row['reference_image_url'] as String?,
      postCreatedAt: _time(row['post_created_at']),
      expiresAt: _time(row['expires_at']),
      postStatus: row['post_status'] as String? ?? 'open',
      moderationRemovedAt: _time(row['moderation_removed_at']),
      ownerDeletedAt: _time(row['owner_deleted_at']),
      reporterId: row['reporter_id'] as String? ?? '',
      reporterName: row['reporter_name'] as String? ?? '',
      reporterUsername: row['reporter_username'] as String? ?? '',
      reporterRole: row['reporter_role'] as String? ?? '',
      reportedUserId: row['reported_user_id'] as String? ?? '',
      reportedName: row['reported_name'] as String? ?? '',
      reportedUsername: row['reported_username'] as String? ?? '',
      reportedRole: row['reported_role'] as String? ?? '',
      reportedAccountStatus: row['reported_account_status'] as String? ?? '',
      confirmedViolations: (row['confirmed_violations'] as num?)?.toInt() ?? 0,
    );
  }
}

class DisabledAccountRecord {
  const DisabledAccountRecord({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
    required this.accountStatus,
    required this.strikeCount,
    required this.disabledAt,
    required this.reason,
  });

  final String userId;
  final String name;
  final String username;
  final String role;
  final String accountStatus;
  final int strikeCount;
  final DateTime? disabledAt;
  final String reason;

  factory DisabledAccountRecord.fromRow(Map<String, dynamic> row) {
    return DisabledAccountRecord(
      userId: row['user_id'] as String? ?? '',
      name: row['full_name'] as String? ?? '',
      username: row['username'] as String? ?? '',
      role: row['role'] as String? ?? '',
      accountStatus: row['account_status'] as String? ?? 'banned',
      strikeCount: (row['strike_count'] as num?)?.toInt() ?? 0,
      disabledAt: _time(row['permanently_disabled_at']),
      reason: row['disable_reason'] as String? ?? '',
    );
  }
}

class LookingForViolationRecord {
  const LookingForViolationRecord({
    required this.id,
    required this.userId,
    required this.postId,
    required this.strikeNumber,
    required this.createdAt,
    this.postTitle,
  });

  final String id;
  final String userId;
  final String postId;
  final int strikeNumber;
  final DateTime createdAt;
  final String? postTitle;

  factory LookingForViolationRecord.fromRow(Map<String, dynamic> row) {
    final post = row['post'];
    String? title;
    if (post is Map) title = post['title'] as String?;
    return LookingForViolationRecord(
      id: row['violation_id'] as String? ?? '',
      userId: row['user_id'] as String? ?? '',
      postId: row['post_id'] as String? ?? '',
      strikeNumber: (row['strike_number'] as num?)?.toInt() ?? 0,
      createdAt: _time(row['created_at']) ?? DateTime.now().toUtc(),
      postTitle: title,
    );
  }
}

String lookingForAdminStatusLabel(String status) => switch (status) {
  'under_review' => 'Under review',
  'action_taken' => 'Confirmed violation',
  'dismissed' => 'Dismissed',
  _ => 'Under review',
};

DateTime? _time(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

class LookingForModerationService {
  LookingForModerationService(this._supabase);

  final SupabaseService _supabase;

  Future<DateTime> serverNow() async {
    try {
      final raw = await _supabase.client.rpc('looking_for_server_now');
      final stamp = DateTime.tryParse(
        supabaseRpcMap(raw)?['now']?.toString() ?? '',
      );
      return stamp?.toUtc() ?? DateTime.now().toUtc();
    } catch (e) {
      debugPrint('LookingForModerationService clock error: $e');
      return DateTime.now().toUtc();
    }
  }

  Future<List<LookingForAdminReport>> listReports() async {
    final rows = await _supabase.client
        .from('admin_looking_for_report_queue')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    return [
      for (final row in rows as List)
        if (row is Map<String, dynamic>) LookingForAdminReport.fromRow(row),
    ];
  }

  Future<LookingForAdminReport?> getReport(String reportId) async {
    final row = await _supabase.client
        .from('admin_looking_for_report_queue')
        .select()
        .eq('report_id', reportId)
        .maybeSingle();
    if (row == null) return null;
    return LookingForAdminReport.fromRow(row);
  }

  Future<String?> decide({
    required String reportId,
    required String decision,
  }) async {
    try {
      final raw = await _supabase.client.rpc(
        'review_looking_for_report',
        params: {'p_report_id': reportId, 'p_decision': decision},
      );
      if (supabaseRpcSuccess(raw)) {
        await AdminAuditService(_supabase).record(
          category: AdminAuditCategory.reportsDisputes,
          eventType: 'looking_for_report_decided',
          status: 'success',
          summary: 'Looking-for report decision saved',
          targetType: 'looking_for_report',
          targetId: reportId,
          details: {'decision': decision},
        );
        return null;
      }
      return supabaseRpcError(
        raw,
        fallback: 'Could not save this decision. Please try again.',
      );
    } catch (e) {
      debugPrint('LookingForModerationService.decide error: $e');
      return 'Could not save this decision. Please try again.';
    }
  }

  Future<List<DisabledAccountRecord>> listDisabledAccounts() async {
    final rows = await _supabase.client
        .from('admin_disabled_accounts')
        .select()
        .order('permanently_disabled_at', ascending: false);
    return [
      for (final row in rows as List)
        if (row is Map<String, dynamic>) DisabledAccountRecord.fromRow(row),
    ];
  }

  Future<List<LookingForViolationRecord>> violationsFor(String userId) async {
    final rows = await _supabase.client
        .from('looking_for_violations')
        .select(
          'violation_id, user_id, post_id, strike_number, created_at, post:looking_for_posts(title)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows as List)
        if (row is Map<String, dynamic>) LookingForViolationRecord.fromRow(row),
    ];
  }
}
