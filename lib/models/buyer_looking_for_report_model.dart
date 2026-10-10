import '../core/utils/report_status.dart';
import 'community_report_model.dart';

class BuyerLookingForReportModel {
  const BuyerLookingForReportModel({
    required this.id,
    required this.postId,
    required this.reporterId,
    required this.reportedUserId,
    required this.reportedUsername,
    required this.reportedDisplayName,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.reporterInstruction,
    this.evidenceAttemptCount = 1,
    this.decisionOutcome,
    this.postTitle = '',
    this.postDescription = '',
    this.snapshotTitle,
    this.snapshotDescription,
    this.snapshotImagePath,
    this.evidence = const [],
  });

  final String id;
  final String postId;
  final String reporterId;
  final String reportedUserId;
  final String reportedUsername;
  final String reportedDisplayName;
  final String reason;
  final String details;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? reporterInstruction;
  final int evidenceAttemptCount;
  final String? decisionOutcome;
  final String postTitle;
  final String postDescription;
  final String? snapshotTitle;
  final String? snapshotDescription;
  final String? snapshotImagePath;
  final List<ReportEvidenceItem> evidence;

  String get displayPostTitle {
    final snap = snapshotTitle?.trim();
    if (snap != null && snap.isNotEmpty) return snap;
    return postTitle.trim();
  }

  String get displayPostDescription {
    final snap = snapshotDescription?.trim();
    if (snap != null && snap.isNotEmpty) return snap;
    return postDescription.trim();
  }

  factory BuyerLookingForReportModel.fromSupabase(
    Map<String, dynamic> row, {
    Map<String, dynamic>? reportedUser,
    List<ReportEvidenceItem> evidence = const [],
  }) {
    final post = row['looking_for_posts'] as Map<String, dynamic>?;
    final user = reportedUser ?? row['reported_user'] as Map<String, dynamic>?;
    final username = user?['username'] as String? ?? '';
    final display =
        user?['full_name'] as String? ??
        (username.isNotEmpty ? username : 'Member');

    DateTime? parseTime(Object? value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return BuyerLookingForReportModel(
      id: row['report_id'] as String? ?? '',
      postId: row['post_id'] as String? ?? '',
      reporterId: row['reporter_id'] as String? ?? '',
      reportedUserId: row['reported_user_id'] as String? ?? '',
      reportedUsername: username,
      reportedDisplayName: display,
      reason: row['reason'] as String? ?? '',
      details: row['details'] as String? ?? '',
      status: reportStatusFromDb(row['status']),
      createdAt: parseTime(row['created_at']) ?? DateTime.now(),
      resolvedAt: parseTime(row['resolved_at']),
      reporterInstruction: row['reporter_instruction'] as String?,
      evidenceAttemptCount:
          (row['evidence_attempt_count'] as num?)?.toInt() ?? 1,
      decisionOutcome: row['decision_outcome'] as String?,
      postTitle: post?['title'] as String? ?? '',
      postDescription: post?['description'] as String? ?? '',
      snapshotTitle: row['snapshot_title'] as String?,
      snapshotDescription: row['snapshot_description'] as String?,
      snapshotImagePath: row['snapshot_image_path'] as String?,
      evidence: evidence,
    );
  }

  BuyerLookingForReportModel copyWith({List<ReportEvidenceItem>? evidence}) {
    return BuyerLookingForReportModel(
      id: id,
      postId: postId,
      reporterId: reporterId,
      reportedUserId: reportedUserId,
      reportedUsername: reportedUsername,
      reportedDisplayName: reportedDisplayName,
      reason: reason,
      details: details,
      status: status,
      createdAt: createdAt,
      resolvedAt: resolvedAt,
      reporterInstruction: reporterInstruction,
      evidenceAttemptCount: evidenceAttemptCount,
      decisionOutcome: decisionOutcome,
      postTitle: postTitle,
      postDescription: postDescription,
      snapshotTitle: snapshotTitle,
      snapshotDescription: snapshotDescription,
      snapshotImagePath: snapshotImagePath,
      evidence: evidence ?? this.evidence,
    );
  }
}
